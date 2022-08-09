// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {IStabilityPool} from "../../interfaces/liquity/IStabilityPool.sol";
import {ISwapRouter} from "../../interfaces/uniswapv3/ISwapRouter.sol";

/**
 * @title Aztec Connect Bridge for Liquity's StabilityPool.sol
 * @author Jan Benes (@benesjan on Github and Telegram)
 * @notice You can use this contract to deposit and withdraw LUSD to and from Liquity's StabilityPool.sol.
 *
 * The contract inherits from OpenZeppelin's implementation of ERC20 token because token balances are used to track
 * the depositor's ownership of the assets controlled by the bridge contract. The token is called StabilityPoolBridge
 * and the token symbol is SPB. During the first deposits an equal amount of SPB tokens is minted as the amount of LUSD
 * deposited - 1 SPB is worth 1 LUSD.  1 SPB token stops being worth 1 LUSD once rewards are claimed. There are 2 types
 * of rewards in the StabilityPool: 1) ETH from liquidations, 2) LQTY from early adopter rewards.
 *
 * See https://docs.liquity.org/faq/stability-pool-and-liquidations#how-do-i-benefit-as-a-stability-provider-from-liquidations[Liquity docs]
 * for more details.
 *
 * Rewards are automatically claimed and swapped to LUSD before each deposit and withdrawal. This allows for precise
 * computation of how much each SPB is worth in terms of LUSD.
 *
 * Note: StabilityPoolBridge.sol is very similar to StakingBridge.sol.
 */
contract StabilityPoolBridge is BridgeBase, ERC20("StabilityPoolBridge", "SPB") {
    error SwapFailed();

    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant LQTY = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // set here because of multihop on Uni

    IStabilityPool public constant STABILITY_POOL = IStabilityPool(0x66017D22b0f8556afDd19FC67041899Eb65a21bb);
    ISwapRouter public constant UNI_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    // The amount of dust to leave in the contract
    // Optimization based on EIP-1087
    uint256 internal constant DUST = 1;

    // Smallest amounts of rewards to swap (gas optimizations)
    // Note: these amounts have to be higher than DUST
    uint256 private constant MIN_LQTY_SWAP_AMT = 1e20; // 100 LQTY tokens
    uint256 private constant MIN_ETH_SWAP_AMT = 1e17; // 0.1 ETH

    address public immutable FRONTEND_TAG; // see StabilityPool.sol for details

    /**
     * @notice Set the addresses of RollupProcessor.sol and front-end tag.
     * @param _rollupProcessor Address of the RollupProcessor.sol
     * @param _frontEndTag An address/tag identifying to which frontend LQTY frontend rewards should go. Can be zero.
     * @dev Frontend tag is set here because there can be only 1 frontend tag per msg.sender in the StabilityPool.sol.
     * See https://docs.liquity.org/faq/frontend-operators#how-do-frontend-tags-work[Liquity docs] for more details.
     */
    constructor(address _rollupProcessor, address _frontEndTag) BridgeBase(_rollupProcessor) {
        FRONTEND_TAG = _frontEndTag;
        _mint(address(this), DUST);
    }

    /**
     * @notice Sets all the important approvals.
     * @dev StabilityPoolBridge never holds LUSD, LQTY, USDC or WETH after or before an invocation of any of its
     * functions. For this reason the following is not a security risk and makes the convert() function more gas
     * efficient.
     */
    function setApprovals() external {
        if (!this.approve(ROLLUP_PROCESSOR, type(uint256).max)) revert ErrorLib.ApproveFailed(address(this));
        if (!IERC20(LUSD).approve(ROLLUP_PROCESSOR, type(uint256).max)) revert ErrorLib.ApproveFailed(LUSD);
        if (!IERC20(LUSD).approve(address(STABILITY_POOL), type(uint256).max)) revert ErrorLib.ApproveFailed(LUSD);
        if (!IERC20(WETH).approve(address(UNI_ROUTER), type(uint256).max)) revert ErrorLib.ApproveFailed(WETH);
        if (!IERC20(LQTY).approve(address(UNI_ROUTER), type(uint256).max)) revert ErrorLib.ApproveFailed(LQTY);
        if (!IERC20(USDC).approve(address(UNI_ROUTER), type(uint256).max)) revert ErrorLib.ApproveFailed(USDC);
    }

    /**
     * @notice Function which deposits or withdraws LUSD to/from StabilityBridge.sol.
     * @dev This method can only be called from the RollupProcessor.sol. If the input asset is LUSD, deposit flow is
     * executed. If SPB, withdrawal. RollupProcessor.sol has to transfer the tokens to the bridge before calling
     * the method. If this is not the case, the function will revert (either in STABILITY_POOL.provideToSP(...) or
     * during SPB burn).
     *
     * Note: The function will revert during withdrawal in case there are troves to be liquidated. I am not handling
     * this scenario because I expect the liquidation bots to be so fast that the scenario will never occur. Checking
     * for it would only waste gas.
     *
     * @param _inputAssetA - LUSD (Deposit) or SPB (Withdrawal)
     * @param _outputAssetA - SPB (Deposit) or LUSD (Withdrawal)
     * @param _totalInputValue - the amount of LUSD to deposit or the amount of SPB to burn and exchange for LUSD
     * @param _auxData - when set to 1 during withdrawals "urgent withdrawal mode" is set (see note bellow)
     * @return outputValueA - the amount of SPB (Deposit) or LUSD (Withdrawal) minted/transferred to
     * the RollupProcessor.sol
     *
     * @dev Note: When swapping rewards fails during withdrawals and "urgent withdrawal mode" is set, the method
     *            doesn't revert and the withdrawer gives up on their claim on the rewards. This mode is present
     *            in order to avoid a scenario when issues with Uniswap pools (lacking liquidity etc.) prevents users
     *            from withdrawing their funds. This mode can't be set upon deposit because it would allow depositors
     *            to steal value from previous bridge depositors. Also the deposit flow being bricked is much less
     *            severe than for withdrawal flow.
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _totalInputValue,
        uint256,
        uint64 _auxData,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256,
            bool
        )
    {
        if (_inputAssetA.erc20Address == LUSD && _outputAssetA.erc20Address == address(this)) {
            // Deposit
            // Provides LUSD to the pool and claim rewards.
            STABILITY_POOL.provideToSP(_totalInputValue, FRONTEND_TAG);
            _swapRewardsToLUSDAndDeposit(false);
            uint256 totalLUSDOwnedBeforeDeposit = STABILITY_POOL.getCompoundedLUSDDeposit(address(this)) -
                _totalInputValue;
            uint256 totalSupply = totalSupply();
            // outputValueA = how much SPB should be minted
            if (totalSupply == 0) {
                // When the totalSupply is 0, I set the SPB/LUSD ratio to be 1.
                outputValueA = _totalInputValue;
            } else {
                // totalSupply / totalLUSDOwnedBeforeDeposit = how much SPB one LUSD is worth
                // When I multiply this ^ with the amount of LUSD deposited I get the amount of SPB to be minted.
                outputValueA = (totalSupply * _totalInputValue) / totalLUSDOwnedBeforeDeposit;
            }
            _mint(address(this), outputValueA);
        } else if (_inputAssetA.erc20Address == address(this) && _outputAssetA.erc20Address == LUSD) {
            // Withdrawal
            // Claim rewards and swap them to LUSD.
            STABILITY_POOL.withdrawFromSP(0);
            _swapRewardsToLUSDAndDeposit(_auxData == 1);

            // stabilityPool.getCompoundedLUSDDeposit(address(this)) / totalSupply() = how much LUSD is one SPB
            // outputValueA = amount of LUSD to be withdrawn and sent to RollupProcessor.sol
            outputValueA = (STABILITY_POOL.getCompoundedLUSDDeposit(address(this)) * _totalInputValue) / totalSupply();
            STABILITY_POOL.withdrawFromSP(outputValueA);
            _burn(address(this), _totalInputValue);
        } else {
            revert ErrorLib.InvalidInput();
        }
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view override(ERC20) returns (uint256) {
        return super.totalSupply() - DUST;
    }

    /*
     * @notice Swaps any ETH and LQTY currently held by the contract to LUSD and deposits LUSD to the StabilityPool.sol.
     * @param _isUrgentWithdrawalMode When set to true the function doesn't revert when the swaps fail.
     * @dev Note: The best route for LQTY -> LUSD is consistently LQTY -> WETH -> USDC -> LUSD. Since I want to swap
     * liquidations rewards (ETH) to LUSD as well, I will first swap LQTY to WETH and then swap it all through USDC to
     * LUSD.
     */
    function _swapRewardsToLUSDAndDeposit(bool _isUrgentWithdrawalMode) internal {
        uint256 lqtyBalance = IERC20(LQTY).balanceOf(address(this));
        if (lqtyBalance > MIN_LQTY_SWAP_AMT) {
            try
                UNI_ROUTER.exactInputSingle(
                    ISwapRouter.ExactInputSingleParams(
                        LQTY,
                        WETH,
                        3000,
                        address(this),
                        block.timestamp,
                        lqtyBalance - DUST,
                        0,
                        0
                    )
                )
            {} catch (bytes memory) {
                if (!_isUrgentWithdrawalMode) {
                    revert SwapFailed();
                }
            }
        }

        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            // Wrap ETH in WETH
            IWETH(WETH).deposit{value: ethBalance}();
        }

        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        if (wethBalance > MIN_ETH_SWAP_AMT) {
            try
                UNI_ROUTER.exactInput(
                    ISwapRouter.ExactInputParams({
                        path: abi.encodePacked(WETH, uint24(500), USDC, uint24(500), LUSD),
                        recipient: address(this),
                        deadline: block.timestamp,
                        amountIn: wethBalance - DUST,
                        amountOutMinimum: 0
                    })
                )
            returns (uint256 lusdBalance) {
                if (lusdBalance != 0) {
                    STABILITY_POOL.provideToSP(lusdBalance, FRONTEND_TAG);
                }
            } catch (bytes memory) {
                if (!_isUrgentWithdrawalMode) {
                    revert SwapFailed();
                }
            }
        }
    }
}
