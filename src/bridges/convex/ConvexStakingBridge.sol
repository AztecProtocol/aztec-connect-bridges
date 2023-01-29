// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";

import {ISubsidy} from "../../aztec/interfaces/ISubsidy.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ICurvePool} from "../../interfaces/curve/ICurvePool.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {IConvexBooster} from "../../interfaces/convex/IConvexBooster.sol";
import {ICurveRewards} from "../../interfaces/convex/ICurveRewards.sol";
import {IRepConvexToken} from "../../interfaces/convex/IRepConvexToken.sol";
import {ICurveExchangeV1} from "../../interfaces/convex/ICurveExchangeV1.sol";
import {ICurveExchangeV2} from "../../interfaces/convex/ICurveExchangeV2.sol";
import {ICurveLiquidityPool} from "../../interfaces/convex/ICurveLiquidityPool.sol";
import {IRollupProcessor} from "rollup-encoder/interfaces/IRollupProcessor.sol";
import {RepresentingConvexToken} from "./RepresentingConvexToken.sol";

/**
 * @notice Bridge allows users stake their Curve LP tokens and earn rewards on them.
 * @dev User earns rewards (CRV, CVX) without locking the staked token in for an extended period of time.
 * If sufficient amount of rewards is collected, rewards are swapped, deposited as liquidity to a Curve Pool through which
 * they earn more Curve LP tokens and these Curve LP tokens are staked.
 * Staking of these converted rewards affects how much is each RCT token worth.
 * User can withdraw (unstake) any time.
 * @dev Convex Finance mints pool specific Convex LP token but not for the staking user (the bridge) directly.
 * RCT ERC20 token is deployed for each loaded pool.
 * RCT is minted proportionally to all, staked and bridge owned, Curve LP tokens.
 * Main purpose of RCT tokens is that they can be owned by the bridge and recovered by the Rollup Processor.
 * @dev Synchronous and stateless bridge
 * @author Vojtech Kaiser (VojtaKai on GitHub)
 */
contract ConvexStakingBridge is BridgeBase {
    using SafeERC20 for IERC20;

    /**
     * @param poolId Id of the staking pool
     * @param convexLpToken Token minted for Convex Finance to track ownership and amount of staked Curve LP tokens
     * @param curveRewards Contract that keeps tracks of minted Convex LP tokens and earned rewards
     */
    struct PoolInfo {
        uint96 poolId;
        address convexLpToken;
        address curveRewards;
    }

    /**
     * @param crvExchangePools Pools to exchange CRV for a token to provide liquidity and earn pool specific Curve LP token
     * @param cvxExchangePools Pools to exchange CVX for a token to provide liquidity and earn pool specific Curve LP token
     * @param liquidityPool Liquidity pool that rewards us with the Curve LP tokens upon depositing liquidity
     */
    struct ExchangePools {
        bytes crvExchangePools;
        bytes cvxExchangePools;
        LiquidityPool liquidityPool;
    }

    /**
     * @param pool Address of the exchange pool that is used to exchange coinIn for coinOut
     * @param coinIn Index of asset deposited
     * @param coinOut Index of asset received
     * @param exchangeInterface Index of interface to use for interaction with exchange pool
     * @param underlying Get underlying asset of coinOut, e.g. get ETH instead of WETH
     * @param tokenToApprove Address of coinIn that exchange pool has to be approved for
     */
    struct ExchangePool {
        address pool;
        uint8 coinIn;
        uint8 coinOut;
        uint8 exchangeInterface;
        bool underlying;
        address tokenToApprove;
    }

    /**
     * @param liquidityPool Address of the liquidity pool that rewards us with the Curve LP tokens upon depositing liquidity
     * @param amountsLength Length of fixed array that describes which coin is depositied as liquidity
     * @param amountsIndex Index of the `amounts` array representing the coin that is deposited
     * @param depositEth Is the deposited liquidity ETH -> true. If a token -> false
     * @param tokenToApprove Address of coinIn that the liquidity pool has to be approved for
     */
    struct LiquidityPool {
        address liquidityPool;
        uint8 amountsLength;
        uint8 amountsIndex;
        bool depositEth;
        address tokenToApprove;
    }

    // Convex Finance Booster
    IConvexBooster public constant BOOSTER = IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31);

    // Representing Convex Token implementation address
    address public immutable RCT_IMPLEMENTATION;

    // Deployed RCT clones, mapping(CurveLpToken => RCT)
    mapping(address => address) public deployedClones;

    // Convex pools that the contract can interact with
    uint256[10] public supportedPools = [23, 25, 32, 33, 38, 40, 49, 61, 64, 122];

    // Exchange pools and a liquidity pool for different pool ids,
    mapping(uint256 => ExchangePools) public exchangePools;

    // (loaded) Convex pools, mapping(CurveLpToken => PoolInfo)
    mapping(address => PoolInfo) public pools;

    // Smallest amounts of rewards to swap (gas optimizations)
    uint256 private constant MIN_CRV_SWAP_AMT = 2e20; // $100
    uint256 private constant MIN_CVX_SWAP_AMT = 3e20; // $100

    // Reward tokens
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    error SwapFailed();
    error PoolAlreadyLoaded(uint256 poolId);
    error UnsupportedPool(uint256 poolId);

    /**
     * @notice Sets the address of the RollupProcessor and deploys RCT token
     * @dev Deploys RCT token implementation
     * @param _rollupProcessor The address of the RollupProcessor to use
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        RCT_IMPLEMENTATION = address(new RepresentingConvexToken());
    }

    /**
     * @notice Empty receive function so the bridge can receive ether. Used for subsidy and possible swap of rewards for ether.
     */
    receive() external payable {}

    /**
     * @notice Stakes Curve LP tokens and earns rewards on them. Gets back RCT token.
     * @dev Convert rate between Curve LP token and corresponding Convex LP token is 1:1.
     * Stake == Deposit, Unstake == Withdraw
     * RCT (Representing Convex Token) is a representation of Convex LP token minted for bridge but fully owned by the bridge.
     * CRV and CXV rewards are swapped for pool specific Curve LP token if sufficient amount has accumulated.
     * @param _inputAssetA Curve LP token (staking), RCT (unstaking)
     * @param _outputAssetA RCT (staking), Curve LP token (unstaking)
     * @param _totalInputValue Number of Curve LP tokens to deposit (staking), number of RCT to withdraw (unstaking)
     * @param _rollupBeneficiary Address of the beneficiary that receives subsidy
     * @return outputValueA Number of RCT minted (staking), Number of Curve LP tokens unstaked (unstaking)
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _totalInputValue,
        uint256,
        uint64,
        address _rollupBeneficiary
    ) external payable override(BridgeBase) onlyRollup returns (uint256 outputValueA, uint256, bool) {
        if (
            _inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20
                || _outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20
        ) {
            revert ErrorLib.InvalidInput();
        }

        if (deployedClones[_inputAssetA.erc20Address] == _outputAssetA.erc20Address) {
            // deposit
            PoolInfo memory selectedPool = pools[_inputAssetA.erc20Address];

            outputValueA = _deposit(_inputAssetA, _outputAssetA, _totalInputValue, selectedPool);
        } else if (deployedClones[_outputAssetA.erc20Address] == _inputAssetA.erc20Address) {
            // withdrawal
            outputValueA = _withdraw(_inputAssetA, _outputAssetA, _totalInputValue);
        } else {
            revert ErrorLib.InvalidInput(); // invalid address or pool has not been loaded yet / RCT token not deployed yet
        }

        // Pays out subsidy to the rollupBeneficiary
        SUBSIDY.claimSubsidy(
            _computeCriteria(_inputAssetA.erc20Address, _outputAssetA.erc20Address), _rollupBeneficiary
        );
    }

    /**
     * @notice Loads pool information for a specific pool and sets up auxiliary services.
     * @dev Loads pool information for a specific pool supported by Convex Finance.
     * Deployment of RCT token for the specific pool is part of the loading.
     * Sets allowance for Booster and Rollup Processor to manipulate bridge's Curve LP tokens and RCT.
     * Sets paths containing different exchange pools to swap rewards for a specific token that is deposited
     * to a liquidity pool to earn pool specific Curve LP tokens that are staked again.
     * Sets allowance for exchange pools and liquidity pools.
     * Sets up bridge subsidy.
     * @param _poolId Id of the pool to load
     */
    function loadPool(uint256 _poolId) external {
        _loadExchangePools(_poolId);

        (address curveLpToken, address convexLpToken,, address curveRewards,,) = BOOSTER.poolInfo(_poolId);
        pools[curveLpToken] = PoolInfo(uint96(_poolId), convexLpToken, curveRewards);

        // deploy RCT clone, log clone address
        address deployedClone = Clones.clone(RCT_IMPLEMENTATION);
        // RCT token initialization - deploy fully working ERC20 RCT token
        RepresentingConvexToken(deployedClone).initialize("RepresentingConvexToken", "RCT");

        deployedClones[curveLpToken] = deployedClone;

        ExchangePools memory exchangePool = exchangePools[_poolId];

        ExchangePool[3] memory _crvExchangePath = abi.decode(exchangePool.crvExchangePools, (ExchangePool[3]));
        ExchangePool[3] memory _cvxExchangePath = abi.decode(exchangePool.cvxExchangePools, (ExchangePool[3]));
        LiquidityPool memory _liquidityPool = exchangePool.liquidityPool;

        // approvals for pool specific tokens
        IERC20(curveLpToken).approve(address(BOOSTER), type(uint256).max);
        IERC20(curveLpToken).approve(ROLLUP_PROCESSOR, type(uint256).max);
        IRepConvexToken(deployedClone).approve(ROLLUP_PROCESSOR, type(uint256).max);

        // approve exchange pools
        for (uint256 i = 0; i < 3; i++) {
            if (_crvExchangePath[i].pool != address(0) && _crvExchangePath[i].tokenToApprove != address(0)) {
                IERC20(_crvExchangePath[i].tokenToApprove).safeApprove(_crvExchangePath[i].pool, 0);
                IERC20(_crvExchangePath[i].tokenToApprove).safeApprove(_crvExchangePath[i].pool, type(uint256).max);
            }
        }
        for (uint256 i = 0; i < 3; i++) {
            if (_cvxExchangePath[i].pool != address(0) && _cvxExchangePath[i].tokenToApprove != address(0)) {
                IERC20(_cvxExchangePath[i].tokenToApprove).safeApprove(_cvxExchangePath[i].pool, 0);
                IERC20(_cvxExchangePath[i].tokenToApprove).safeApprove(_cvxExchangePath[i].pool, type(uint256).max);
            }
        }

        // approve liquidity pool (only one token can be deposited)
        if (_liquidityPool.tokenToApprove != address(0)) {
            try IERC20(_liquidityPool.tokenToApprove).approve(_liquidityPool.liquidityPool, type(uint256).max) {}
            catch {
                // already approved
            }
        }

        // subsidy
        uint256[] memory criterias = new uint256[](2);
        uint32[] memory gasUsage = new uint32[](2);
        uint32[] memory minGasPerMinute = new uint32[](2);

        criterias[0] = uint256(keccak256(abi.encodePacked(curveLpToken, deployedClone)));
        criterias[1] = uint256(keccak256(abi.encodePacked(deployedClone, curveLpToken)));
        gasUsage[0] = 1000000;
        gasUsage[1] = 1000000;
        minGasPerMinute[0] = 700;
        minGasPerMinute[1] = 700;

        SUBSIDY.setGasUsageAndMinGasPerMinute(criterias, gasUsage, minGasPerMinute);
    }

    /**
     * @notice Loads pool specific exchange pools and liquidity pool. Unsupported pools will revert.
     * @dev usdtTo3Crv had to be tweaked to fit the Exchange Pool interface because it uses a different method to get the 3CRV token than the rest
     */
    function _loadExchangePools(uint256 _poolId) internal {
        ExchangePool[3] memory crvPath;
        ExchangePool[3] memory cvxPath;
        LiquidityPool memory liquidityPool;

        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address usdt = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        address crv3 = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;

        ExchangePool memory crvToEth = ExchangePool(0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511, 1, 0, 1, true, CRV); // CRV -> ETH
        ExchangePool memory crvToWeth = ExchangePool(0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511, 1, 0, 1, false, CRV); // CRV -> WETH
        ExchangePool memory cvxToEth = ExchangePool(0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4, 1, 0, 1, true, CVX); // CVX -> ETH
        ExchangePool memory cvxToWeth = ExchangePool(0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4, 1, 0, 1, false, CVX); // CVX -> WETH
        ExchangePool memory wethToUsdt = ExchangePool(0xD51a44d3FaE010294C616388b506AcdA1bfAAE46, 2, 0, 2, false, weth); // WETH -> USDT
        ExchangePool memory usdtTo3Crv = ExchangePool(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7, 2, 0, 3, false, usdt); // Deposit USDT, earn 3Crv

        if (_poolId == 25) {
            crvPath[0] = crvToEth;
            cvxPath[0] = cvxToEth;
            liquidityPool = LiquidityPool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022, 2, 0, true, address(0));
        } else if (_poolId == 32) {
            crvPath[0] = crvToWeth;
            crvPath[1] = wethToUsdt;
            crvPath[2] = usdtTo3Crv;
            cvxPath[0] = cvxToWeth;
            cvxPath[1] = wethToUsdt;
            cvxPath[2] = usdtTo3Crv;
            liquidityPool = LiquidityPool(0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B, 2, 1, false, crv3);
        } else if (_poolId == 38) {
            crvPath[0] = crvToWeth;
            cvxPath[0] = cvxToWeth;
            liquidityPool = LiquidityPool(0xD51a44d3FaE010294C616388b506AcdA1bfAAE46, 3, 2, false, weth);
        } else if (_poolId == 40) {
            crvPath[0] = crvToWeth;
            crvPath[1] = wethToUsdt;
            crvPath[2] = usdtTo3Crv;
            cvxPath[0] = cvxToWeth;
            cvxPath[1] = wethToUsdt;
            cvxPath[2] = usdtTo3Crv;
            liquidityPool = LiquidityPool(0x5a6A4D54456819380173272A5E8E9B9904BdF41B, 2, 1, false, crv3);
        } else if (_poolId == 61) {
            crvPath[0] = crvToWeth;
            cvxPath[0] = cvxToWeth;
            liquidityPool = LiquidityPool(0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511, 2, 0, false, weth);
        } else if (_poolId == 64) {
            crvPath[0] = crvToWeth;
            cvxPath[0] = cvxToWeth;
            liquidityPool = LiquidityPool(0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4, 2, 0, false, weth);
        } else if (_poolId == 49) {
            crvPath[0] = crvToEth;
            cvxPath[0] = cvxToEth;
            liquidityPool = LiquidityPool(0xC4C319E2D4d66CcA4464C0c2B32c9Bd23ebe784e, 2, 0, true, address(0));
        } else if (_poolId == 23) {
            crvPath[0] = crvToEth;
            cvxPath[0] = cvxToEth;
            liquidityPool = LiquidityPool(0xc5424B857f758E906013F3555Dad202e4bdB4567, 2, 0, true, address(0));
        } else if (_poolId == 33) {
            crvPath[0] = crvToWeth;
            crvPath[1] = wethToUsdt;
            crvPath[2] = usdtTo3Crv;
            cvxPath[0] = cvxToWeth;
            cvxPath[1] = wethToUsdt;
            cvxPath[2] = usdtTo3Crv;
            liquidityPool = LiquidityPool(0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA, 2, 1, false, crv3);
        } else if (_poolId == 122) {
            crvPath[0] = crvToEth;
            cvxPath[0] = cvxToEth;
            liquidityPool = LiquidityPool(0x9848482da3Ee3076165ce6497eDA906E66bB85C5, 2, 0, true, address(0));
        } else {
            revert UnsupportedPool(_poolId);
        }

        if (exchangePools[_poolId].liquidityPool.liquidityPool != address(0)) {
            revert PoolAlreadyLoaded(_poolId);
        }

        exchangePools[_poolId] = ExchangePools(abi.encode(crvPath), abi.encode(cvxPath), liquidityPool);
    }

    /**
     * @notice Computes the criteria that is passed when claiming subsidy.
     * @param _inputAssetA The input asset
     * @param _outputAssetA The output asset
     * @return The criteria
     */
    function computeCriteria(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint64
    ) public pure override(BridgeBase) returns (uint256) {
        return _computeCriteria(_inputAssetA.erc20Address, _outputAssetA.erc20Address);
    }

    /**
     * @notice Deposits Curve LP tokens
     * @dev Proportional amount of RCT is minted for the staked amount of Curve LP tokens.
     * @param _inputAssetA Asset for the Curve LP token
     * @param _outputAssetA Asset for the RCT token
     * @param _totalInputValue Number of Curve LP tokens to stake
     * @param _selectedPool Pool info about the staking pool
     * @return outputValueA Number of minted RCT tokens
     */
    function _deposit(
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory _outputAssetA,
        uint256 _totalInputValue,
        PoolInfo memory _selectedPool
    ) internal returns (uint256 outputValueA) {
        uint256 unstakedRewardLpTokens = IERC20(_inputAssetA.erc20Address).balanceOf(address(this)) - _totalInputValue;
        uint256 rewardLpTokens = _swapRewardsToCurveLpToken(_selectedPool, _inputAssetA.erc20Address);

        BOOSTER.deposit(_selectedPool.poolId, _totalInputValue + rewardLpTokens + unstakedRewardLpTokens, true);

        uint256 totalSupplyRCT = IRepConvexToken(_outputAssetA.erc20Address).totalSupply();
        if (totalSupplyRCT == 0) {
            // Initial `RCT/Curve LP token` staking ratio is set to 1
            outputValueA = _totalInputValue;
        } else {
            uint256 totalCurveLpTokensOwnedBeforeDeposit =
                ICurveRewards(_selectedPool.curveRewards).balanceOf(address(this)) - _totalInputValue;
            // totalSupplyRCT / totalCurveLpTokensOwnedBeforeDeposit = how many RCT is one Curve LP token worth
            // When this ^ is multiplied by the amount of Curve LP tokens deposited in this tx alone, you get the amount of RCT to be minted.
            outputValueA = (totalSupplyRCT * _totalInputValue) / totalCurveLpTokensOwnedBeforeDeposit;
        }

        IRepConvexToken(_outputAssetA.erc20Address).mint(outputValueA);
    }

    /**
     * @notice Withdraws Curve LP tokens
     * @dev RCT is burned for the bridge. Proportional amount of Curve LP tokens is withdrawn
     * @param _inputAssetA Asset for the RCT token
     * @param _outputAssetA Asset for the Curve LP token
     * @param _totalInputValue Number of RCT to burn
     * @return outputValueA Number of withdrawn Curve LP tokens
     */
    function _withdraw(
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory _outputAssetA,
        uint256 _totalInputValue
    ) internal returns (uint256 outputValueA) {
        PoolInfo memory selectedPool = pools[_outputAssetA.erc20Address];
        uint256 unstakedRewardLpTokens = IERC20(_outputAssetA.erc20Address).balanceOf(address(this));
        uint256 rewardLpTokens = _swapRewardsToCurveLpToken(selectedPool, _outputAssetA.erc20Address); // will not be staked now, will be staked with next deposit

        uint256 totalSupplyRCT = IRepConvexToken(_inputAssetA.erc20Address).totalSupply();

        // How many Curve LP tokens to withdraw. How many Curve LP tokens is 1 RCT worth, times number of RCT to withdraw
        outputValueA = (
            ICurveRewards(selectedPool.curveRewards).balanceOf(address(this)) + rewardLpTokens + unstakedRewardLpTokens
        ) * _totalInputValue / totalSupplyRCT;
        // Transfer Convex LP tokens from CrvRewards back to the bridge
        ICurveRewards(selectedPool.curveRewards).withdraw(outputValueA, false); // rewards are not claimed again

        BOOSTER.withdraw(selectedPool.poolId, outputValueA);

        IRepConvexToken(_inputAssetA.erc20Address).burn(_totalInputValue);
    }

    /**
     * @notice Exchanges x amount of token A for y amount of token B via Curve pools
     * @param _pool Exchange pool
     * @param _amount Amount of token A to exchange
     * @return totalExchangedAmt Amount of token B received
     * @dev Exchange pool is set up at pool loading
     * @dev Exchange pool determines which interface is going to be used
     */
    function _exchangeCoins(ExchangePool memory _pool, uint256 _amount) internal returns (uint256 totalExchangedAmt) {
        if (_pool.exchangeInterface == 1 && _pool.underlying) {
            try ICurveExchangeV1(_pool.pool).exchange_underlying(_pool.coinIn, _pool.coinOut, _amount, 0) returns (
                uint256 exchangedTokensAmt
            ) {
                totalExchangedAmt = exchangedTokensAmt;
            } catch (bytes memory) {
                revert SwapFailed();
            }
        } else if (_pool.exchangeInterface == 1) {
            try ICurveExchangeV1(_pool.pool).exchange(_pool.coinIn, _pool.coinOut, _amount, 0) returns (
                uint256 exchangedTokensAmt
            ) {
                totalExchangedAmt = exchangedTokensAmt;
            } catch (bytes memory) {
                revert SwapFailed();
            }
        } else if (_pool.exchangeInterface == 2) {
            uint256 usdtBalanceBefore = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7).balanceOf(address(this));
            try ICurveExchangeV2(_pool.pool).exchange(_pool.coinIn, _pool.coinOut, _amount, 0, false) {
                uint256 usdtBalanceAfter = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7).balanceOf(address(this));
                totalExchangedAmt = usdtBalanceAfter - usdtBalanceBefore;
            } catch (bytes memory) {
                revert SwapFailed();
            }
        } else if (_pool.exchangeInterface == 3) {
            uint256[3] memory amounts;
            amounts[_pool.coinIn] = _amount;
            uint256 crv3BalanceBefore = IERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490).balanceOf(address(this));
            ICurveLiquidityPool(_pool.pool).add_liquidity(amounts, 0);
            totalExchangedAmt =
                IERC20(0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490).balanceOf(address(this)) - crv3BalanceBefore;
        }
    }

    /**
     * @notice Swaps rewards and provides liquidity to earn pool specific Curve LP tokens
     * @dev Minimum amount of rewards had to accumulate in order to perform the exchange
     * @dev Exchange and liquidity pools are set up at pool loading
     */
    function _swapRewardsToCurveLpToken(PoolInfo memory _selectedPool, address _curveLpToken)
        internal
        returns (uint256 lpTokenAmt)
    {
        ICurveRewards(_selectedPool.curveRewards).getReward(address(this), true); // claim rewards

        uint256 totalExchangedAmt;
        bool exchangePoolsLoaded;

        ExchangePools memory exchangePool;

        uint256 crvBalance = IERC20(CRV).balanceOf(address(this));
        if (crvBalance > MIN_CRV_SWAP_AMT) {
            exchangePool = exchangePools[_selectedPool.poolId];
            exchangePoolsLoaded = true;
            ExchangePool[3] memory crvExchangePools = abi.decode(exchangePool.crvExchangePools, (ExchangePool[3]));

            uint256 exchangedAmt;

            for (uint256 i = 0; i < 3; i++) {
                if (crvExchangePools[i].pool != address(0) && i == 0) {
                    exchangedAmt = _exchangeCoins(crvExchangePools[i], crvBalance);
                } else if (crvExchangePools[i].pool != address(0)) {
                    exchangedAmt = _exchangeCoins(crvExchangePools[i], exchangedAmt);
                }
            }

            totalExchangedAmt = exchangedAmt;
        }

        uint256 cvxBalance = IERC20(CVX).balanceOf(address(this));
        if (cvxBalance > MIN_CVX_SWAP_AMT) {
            if (!exchangePoolsLoaded) {
                exchangePool = exchangePools[_selectedPool.poolId];
            }

            ExchangePool[3] memory cvxExchangePools = abi.decode(exchangePool.cvxExchangePools, (ExchangePool[3]));

            uint256 exchangedAmt;

            for (uint256 i = 0; i < 3; i++) {
                if (cvxExchangePools[i].pool != address(0) && i == 0) {
                    exchangedAmt = _exchangeCoins(cvxExchangePools[i], cvxBalance);
                } else if (cvxExchangePools[i].pool != address(0)) {
                    exchangedAmt = _exchangeCoins(cvxExchangePools[i], exchangedAmt);
                }
            }

            totalExchangedAmt += exchangedAmt;
        }

        // deposit exchanged tokens (ETH) to liquidity pool to receive Curve LP token
        if (totalExchangedAmt != 0) {
            LiquidityPool memory lp = exchangePool.liquidityPool;

            if (lp.amountsLength == 2) {
                uint256[2] memory amounts;
                amounts[lp.amountsIndex] = totalExchangedAmt;

                lpTokenAmt = lp.depositEth
                    ? ICurveLiquidityPool(lp.liquidityPool).add_liquidity{value: amounts[lp.amountsIndex]}(amounts, 0)
                    : ICurveLiquidityPool(lp.liquidityPool).add_liquidity(amounts, 0);
            } else if (lp.amountsLength == 3) {
                uint256[3] memory amounts;
                amounts[lp.amountsIndex] = totalExchangedAmt;

                uint256 curveLpTokensBeforeDeposit = IERC20(_curveLpToken).totalSupply();
                ICurveLiquidityPool(lp.liquidityPool).add_liquidity(amounts, 0);
                lpTokenAmt = IERC20(_curveLpToken).totalSupply() - curveLpTokensBeforeDeposit;
            }
        }
    }

    /**
     * @notice Computes the criteria that is passed when claiming subsidy.
     * @param _inputToken The input asset address
     * @param _outputToken The output asset address
     * @return The criteria
     */
    function _computeCriteria(address _inputToken, address _outputToken) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_inputToken, _outputToken)));
    }
}
