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
import {InflationProtection} from "../../libraries/convex/InflationProtection.sol";

/**
 * @notice Bridge allows users stake their Curve LP tokens and earn rewards on them.
 * @dev User earns rewards (CRV, CVX) without locking the staked token in for an extended period of time.
 * If sufficient amount of rewards is collected, rewards are swapped, deposited as liquidity to a Curve Pool through which
 * they earn more Curve LP tokens and these Curve LP tokens are staked.
 * Staking of these converted rewards affects how much is each RCT token worth.
 * User can withdraw (unstake) any time.
 * @dev Convex Finance mints pool specific Convex LP token but not for the staking user (the bridge) directly.
 * RCT ERC20 token is deployed for each loaded pool.
 * RCT (share) is minted proportionally to all, staked and bridge owned, Curve LP tokens (assets) in 1e10 : 1 ratio.
 * Main purpose of RCT tokens is that they can be owned by the bridge and recovered by the Rollup Processor.
 * @dev Synchronous and stateful bridge
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

    // Reward tokens
    address public constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address public constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    // Exchange tokens
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant CRV3 = 0x6c3F90f043a72FA612cbac8115EE7e52BDe6E490;

    // Exchange pools
    address public constant CRV_TO_ETH_POOL = 0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511;
    address public constant CVX_TO_ETH_POOL = 0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4;
    address public constant WETH_TO_USDT_POOL = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;
    address public constant USDT_TO_3CRV_POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;

    // Liquidity pools
    address public constant ST_ETH_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address public constant FRAX_POOL = 0xd632f22692FaC7611d2AA1C0D552930D43CAEd3B;
    address public constant TRI_CRYPTO_2_POOL = 0xD51a44d3FaE010294C616388b506AcdA1bfAAE46;
    address public constant MIM_POOL = 0x5a6A4D54456819380173272A5E8E9B9904BdF41B;
    address public constant CRV_ETH_POOL = 0x8301AE4fc9c624d1D396cbDAa1ed877821D7C511;
    address public constant CVX_ETH_POOL = 0xB576491F1E6e5E62f1d8F26062Ee822B40B0E0d4;
    address public constant AL_ETH_POOL = 0xC4C319E2D4d66CcA4464C0c2B32c9Bd23ebe784e;
    address public constant S_ETH_POOL = 0xc5424B857f758E906013F3555Dad202e4bdB4567;
    address public constant LUSD_POOL = 0xEd279fDD11cA84bEef15AF5D39BB4d4bEE23F0cA;
    address public constant P_ETH_POOL = 0x9848482da3Ee3076165ce6497eDA906E66bB85C5;

    // Init deposit limit
    uint256 private constant INIT_DEPOSIT_LIMIT = 1e16;

    // Smallest amounts of rewards to swap (gas optimizations)
    uint256 private constant MIN_SWAP_AMT = 25e18; // $25 for CRV, $145 for CVX

    // Representing Convex Token implementation address
    address public immutable RCT_IMPLEMENTATION;

    // Deployed RCT clones, mapping(CurveLpToken => RCT)
    mapping(address => address) public deployedClones;

    // Exchange pools and a liquidity pool for different pool ids,
    mapping(uint256 => ExchangePools) public exchangePools;

    // (loaded) Convex pools, mapping(CurveLpToken => PoolInfo)
    mapping(address => PoolInfo) public pools;

    event ExchangePoolsSetup(uint256 poolId);

    error PoolAlreadyLoaded(uint256 poolId);
    error UnsupportedPool(uint256 poolId);
    error InsufficientFirstDepositAmount();

    /**
     * @notice Sets the address of the RollupProcessor and deploys RCT token
     * @dev Deploys RCT token implementation
     * @param _rollupProcessor The address of the RollupProcessor to use
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        RCT_IMPLEMENTATION = address(new RepresentingConvexToken());
    }

    /**
     * @notice Empty receive function so the bridge can receive ether. Used by some reward swaps.
     */
    receive() external payable {}

    /**
     * @notice Stakes Curve LP tokens and earns rewards on them. Gets back RCT token.
     * @dev Curve LP token = asset, RCT token = share
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
     * @notice Loads pool specific exchange pools and liquidity pool. Unsupported pools and already loaded pools will revert.
     * @dev USDT -> 3Crv had to be tweaked to fit the Exchange Pool interface because it uses a different method to get the 3Crv token than the rest
     * @dev ExchangePool(exchange pool address, coin in, coin out, exchange interface, get underlying asset, token the exchange pool will transfer if exchange takes place)
     * @dev LiquidityPool(liquidity pool address, array length, index of the deposited coin in the array, is deposit ETH or a token, token the liquidity pool will transfer if exchange takes place)
     */
    function _loadExchangePools(uint256 _poolId) internal {
        if (exchangePools[_poolId].liquidityPool.liquidityPool != address(0)) {
            revert PoolAlreadyLoaded(_poolId);
        }

        ExchangePool[3] memory crvPath;
        ExchangePool[3] memory cvxPath;
        LiquidityPool memory liquidityPool;

        if (_poolId == 25) {
            crvPath[0] = ExchangePool(CRV_TO_ETH_POOL, 1, 0, 1, true, CRV); // CRV -> ETH
            cvxPath[0] = ExchangePool(CVX_TO_ETH_POOL, 1, 0, 1, true, CVX); // CVX -> ETH
            liquidityPool = LiquidityPool(ST_ETH_POOL, 2, 0, true, address(0)); // Deposit ETH, earn Curve LP token
        } else if (_poolId == 32) {
            crvPath[0] = ExchangePool(CRV_TO_ETH_POOL, 1, 0, 1, false, CRV); // CRV -> WETH
            crvPath[1] = ExchangePool(WETH_TO_USDT_POOL, 2, 0, 2, false, WETH); // WETH -> USDT
            crvPath[2] = ExchangePool(USDT_TO_3CRV_POOL, 2, 0, 3, false, USDT); // Deposit USDT, earn 3Crv
            cvxPath[0] = ExchangePool(CVX_TO_ETH_POOL, 1, 0, 1, false, CVX); // CVX -> WETH
            cvxPath[1] = ExchangePool(WETH_TO_USDT_POOL, 2, 0, 2, false, WETH); // WETH -> USDT
            cvxPath[2] = ExchangePool(USDT_TO_3CRV_POOL, 2, 0, 3, false, USDT); // Deposit USDT, earn 3Crv
            liquidityPool = LiquidityPool(FRAX_POOL, 2, 1, false, CRV3); // Deposit 3Crv, earn Curve LP token
        } else if (_poolId == 38) {
            crvPath[0] = ExchangePool(CRV_TO_ETH_POOL, 1, 0, 1, false, CRV); // CRV -> WETH
            cvxPath[0] = ExchangePool(CVX_TO_ETH_POOL, 1, 0, 1, false, CVX); // CVX -> WETH
            liquidityPool = LiquidityPool(TRI_CRYPTO_2_POOL, 3, 2, false, WETH); // Deposit WETH, earn Curve LP token
        } else if (_poolId == 40) {
            crvPath[0] = ExchangePool(CRV_TO_ETH_POOL, 1, 0, 1, false, CRV); // CRV -> WETH
            crvPath[1] = ExchangePool(WETH_TO_USDT_POOL, 2, 0, 2, false, WETH); // WETH -> USDT
            crvPath[2] = ExchangePool(USDT_TO_3CRV_POOL, 2, 0, 3, false, USDT); // Deposit USDT, earn 3Crv
            cvxPath[0] = ExchangePool(CVX_TO_ETH_POOL, 1, 0, 1, false, CVX); // CVX -> WETH
            cvxPath[1] = ExchangePool(WETH_TO_USDT_POOL, 2, 0, 2, false, WETH); // WETH -> USDT
            cvxPath[2] = ExchangePool(USDT_TO_3CRV_POOL, 2, 0, 3, false, USDT); // Deposit USDT, earn 3Crv
            liquidityPool = LiquidityPool(MIM_POOL, 2, 1, false, CRV3); // Deposit 3Crv, earn Curve LP token
        } else if (_poolId == 61) {
            crvPath[0] = ExchangePool(CRV_TO_ETH_POOL, 1, 0, 1, false, CRV); // CRV -> WETH
            cvxPath[0] = ExchangePool(CVX_TO_ETH_POOL, 1, 0, 1, false, CVX); // CVX -> WETH
            liquidityPool = LiquidityPool(CRV_ETH_POOL, 2, 0, false, WETH); // Deposit WETH, earn Curve LP token
        } else if (_poolId == 64) {
            crvPath[0] = ExchangePool(CRV_TO_ETH_POOL, 1, 0, 1, false, CRV); // CRV -> WETH
            cvxPath[0] = ExchangePool(CVX_TO_ETH_POOL, 1, 0, 1, false, CVX); // CVX -> WETH
            liquidityPool = LiquidityPool(CVX_ETH_POOL, 2, 0, false, WETH); // Deposit WETH, earn Curve LP token
        } else if (_poolId == 49) {
            crvPath[0] = ExchangePool(CRV_TO_ETH_POOL, 1, 0, 1, true, CRV); // CRV -> ETH
            cvxPath[0] = ExchangePool(CVX_TO_ETH_POOL, 1, 0, 1, true, CVX); // CVX -> ETH
            liquidityPool = LiquidityPool(AL_ETH_POOL, 2, 0, true, address(0)); // Deposit ETH, earn Curve LP token
        } else if (_poolId == 23) {
            crvPath[0] = ExchangePool(CRV_TO_ETH_POOL, 1, 0, 1, true, CRV); // CRV -> ETH
            cvxPath[0] = ExchangePool(CVX_TO_ETH_POOL, 1, 0, 1, true, CVX); // CVX -> ETH
            liquidityPool = LiquidityPool(S_ETH_POOL, 2, 0, true, address(0)); // Deposit ETH, earn Curve LP token
        } else if (_poolId == 33) {
            crvPath[0] = ExchangePool(CRV_TO_ETH_POOL, 1, 0, 1, false, CRV); // CRV -> WETH
            crvPath[1] = ExchangePool(WETH_TO_USDT_POOL, 2, 0, 2, false, WETH); // WETH -> USDT
            crvPath[2] = ExchangePool(USDT_TO_3CRV_POOL, 2, 0, 3, false, USDT); // Deposit USDT, earn 3Crv
            cvxPath[0] = ExchangePool(CVX_TO_ETH_POOL, 1, 0, 1, false, CVX); // CVX -> WETH
            cvxPath[1] = ExchangePool(WETH_TO_USDT_POOL, 2, 0, 2, false, WETH); // WETH -> USDT
            cvxPath[2] = ExchangePool(USDT_TO_3CRV_POOL, 2, 0, 3, false, USDT); // Deposit USDT, earn 3Crv
            liquidityPool = LiquidityPool(LUSD_POOL, 2, 1, false, CRV3); // Deposit 3Crv, earn Curve LP token
        } else if (_poolId == 122) {
            crvPath[0] = ExchangePool(CRV_TO_ETH_POOL, 1, 0, 1, true, CRV); // CRV -> ETH
            cvxPath[0] = ExchangePool(CVX_TO_ETH_POOL, 1, 0, 1, true, CVX); // CVX -> ETH
            liquidityPool = LiquidityPool(P_ETH_POOL, 2, 0, true, address(0)); // Deposit ETH, earn Curve LP token
        } else {
            revert UnsupportedPool(_poolId);
        }

        exchangePools[_poolId] = ExchangePools(abi.encode(crvPath), abi.encode(cvxPath), liquidityPool);

        emit ExchangePoolsSetup(_poolId);
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
     * @notice Deposits assets (Curve LP tokens)
     * @dev Shares (RCT) minted for the staked assets (Curve LP tokens)
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
        uint256 totalSupplyRCT = IRepConvexToken(_outputAssetA.erc20Address).totalSupply();
        if (totalSupplyRCT == 0 && _totalInputValue < INIT_DEPOSIT_LIMIT) {
            revert InsufficientFirstDepositAmount();
        }
        uint256 unstakedRewardLpTokens = IERC20(_inputAssetA.erc20Address).balanceOf(address(this)) - _totalInputValue;
        uint256 rewardLpTokens = _swapRewardsToCurveLpToken(_selectedPool, _inputAssetA.erc20Address);

        BOOSTER.deposit(_selectedPool.poolId, _totalInputValue + rewardLpTokens + unstakedRewardLpTokens, true);

        if (totalSupplyRCT == 0) {
            // Initial `RCT/Curve LP token` staking ratio is set to 1e10:1
            outputValueA = InflationProtection._convertToShares(_totalInputValue, 0, 0);
        } else {
            uint256 totalCurveLpTokensOwnedBeforeDeposit =
                ICurveRewards(_selectedPool.curveRewards).balanceOf(address(this)) - _totalInputValue;
            // totalSupplyRCT / totalCurveLpTokensOwnedBeforeDeposit = how many RCT is one Curve LP token worth
            outputValueA = InflationProtection._convertToShares(
                _totalInputValue, totalSupplyRCT, totalCurveLpTokensOwnedBeforeDeposit
            );
        }

        IRepConvexToken(_outputAssetA.erc20Address).mint(outputValueA);
    }

    /**
     * @notice Withdraws assets (Curve LP tokens)
     * @dev Shares (RCT) are burned for the bridge. Corresponding amount of assets (Curve LP tokens) is withdrawn.
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
        uint256 totalCurveLpTokens =
            ICurveRewards(selectedPool.curveRewards).balanceOf(address(this)) + rewardLpTokens + unstakedRewardLpTokens;
        // How many Curve LP tokens to withdraw.
        outputValueA = InflationProtection._convertToAssets(_totalInputValue, totalSupplyRCT, totalCurveLpTokens);
        // Transfer Convex LP tokens from CurveRewards back to the bridge
        ICurveRewards(selectedPool.curveRewards).withdraw(outputValueA, false); // rewards are not claimed again

        BOOSTER.withdraw(selectedPool.poolId, outputValueA);

        IRepConvexToken(_inputAssetA.erc20Address).burn(_totalInputValue);
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

        uint256 crvBalance = IERC20(CRV).balanceOf(address(this));
        uint256 cvxBalance = IERC20(CVX).balanceOf(address(this));

        if (crvBalance < MIN_SWAP_AMT || cvxBalance < MIN_SWAP_AMT) {
            return 0;
        }

        ExchangePools memory exchangePool = exchangePools[_selectedPool.poolId];

        ExchangePool[3] memory crvExchangePools = abi.decode(exchangePool.crvExchangePools, (ExchangePool[3]));
        ExchangePool[3] memory cvxExchangePools = abi.decode(exchangePool.cvxExchangePools, (ExchangePool[3]));

        uint256 exchangedAmtFromCRV;
        uint256 exchangedAmtFromCVX;

        for (uint256 i = 0; i < 3; i++) {
            if (crvExchangePools[i].pool != address(0)) {
                exchangedAmtFromCRV = i == 0
                    ? _exchangeCoins(crvExchangePools[i], crvBalance)
                    : _exchangeCoins(crvExchangePools[i], exchangedAmtFromCRV);
            }
            if (cvxExchangePools[i].pool != address(0)) {
                exchangedAmtFromCVX = i == 0
                    ? _exchangeCoins(cvxExchangePools[i], cvxBalance)
                    : _exchangeCoins(cvxExchangePools[i], exchangedAmtFromCVX);
            }
        }

        uint256 totalExchangedAmt = exchangedAmtFromCRV + exchangedAmtFromCVX;

        // deposit exchanged tokens / ETH to liquidity pool to receive Curve LP token
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

    /**
     * @notice Exchanges x amount of token A for y amount of token B via Curve pools
     * @param _pool Exchange pool
     * @param _amount Amount of token A to exchange
     * @return exchangedAmt Amount of token B received
     * @dev Exchange pool is set up at pool loading
     * @dev Exchange pool determines which interface is going to be used
     */
    function _exchangeCoins(ExchangePool memory _pool, uint256 _amount) internal returns (uint256 exchangedAmt) {
        if (_pool.exchangeInterface == 1 && _pool.underlying) {
            exchangedAmt = ICurveExchangeV1(_pool.pool).exchange_underlying(_pool.coinIn, _pool.coinOut, _amount, 0);
        } else if (_pool.exchangeInterface == 1) {
            exchangedAmt = ICurveExchangeV1(_pool.pool).exchange(_pool.coinIn, _pool.coinOut, _amount, 0);
        } else if (_pool.exchangeInterface == 2) {
            uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(address(this));
            ICurveExchangeV2(_pool.pool).exchange(_pool.coinIn, _pool.coinOut, _amount, 0, false);
            uint256 usdtBalanceAfter = IERC20(USDT).balanceOf(address(this));
            exchangedAmt = usdtBalanceAfter - usdtBalanceBefore;
        } else if (_pool.exchangeInterface == 3) {
            uint256[3] memory amounts;
            amounts[_pool.coinIn] = _amount;
            uint256 crv3BalanceBefore = IERC20(CRV3).balanceOf(address(this));
            ICurveLiquidityPool(_pool.pool).add_liquidity(amounts, 0);
            exchangedAmt = IERC20(CRV3).balanceOf(address(this)) - crv3BalanceBefore;
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
