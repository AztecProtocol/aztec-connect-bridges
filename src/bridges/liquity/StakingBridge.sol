// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {ILQTYStaking} from "../../interfaces/liquity/ILQTYStaking.sol";
import {ISwapRouter} from "../../interfaces/uniswapv3/ISwapRouter.sol";

/**
 * @title Aztec Connect Bridge for Liquity's LQTYStaking.sol
 * @author Jan Benes (@benesjan on Github and Telegram)
 * @notice You can use this contract to stake and unstake LQTY to and from LQTY staking contract.
 *
 * The contract inherits from OpenZeppelin's implementation of ERC20 token because token balances are used to track
 * the depositor's ownership of the assets controlled by the bridge contract. The token is called LQTYStaking and
 * the token symbol is SB. During the first deposits an equal amount of SB tokens is minted as the amount of LQTY
 * deposited - 1 SB is worth 1 LQTY.  1 SB token stops being worth 1 LQTY once rewards are claimed. There are 2 types
 * of rewards in the LQTYStaking.sol: LUSD and ETH (see https://docs.liquity.org/faq/staking[Liquity docs] for more
 * details).
 *
 * Rewards are automatically claimed and swapped to LQTY before staking and unstaking. This allows for precise
 * computation of how much each SB is worth in terms of LQTY.
 *
 * Note: StakingBridge.sol is very similar to StabilityPoolBridge.sol.
 */
contract StakingBridge is BridgeBase, ERC20("StakingBridge", "SB") {
    error SwapFailed();

    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant LQTY = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // set here because of multihop on Uni

    ILQTYStaking public constant STAKING_CONTRACT = ILQTYStaking(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    ISwapRouter public constant UNI_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    // The amount of dust to leave in the contract
    // Optimization based on EIP-1087
    uint256 internal constant DUST = 1;

    // Smallest amounts of rewards to swap (gas optimizations)
    // Note: these amounts have to be higher than DUST
    uint256 private constant MIN_LUSD_SWAP_AMT = 1e20; // 100 LUSD
    uint256 private constant MIN_ETH_SWAP_AMT = 1e17; // 0.1 ETH

    /**
     * @notice Set the address of RollupProcessor.sol.
     * @param _rollupProcessor Address of the RollupProcessor.sol
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        _mint(address(this), DUST);
    }

    receive() external payable {}

    fallback() external payable {}

    /**
     * @notice Sets all the important approvals.
     * @dev StakingBridge never holds LUSD, LQTY, USDC or WETH after or before an invocation of any of its functions.
     * For this reason the following is not a security risk and makes the convert() function more gas efficient.
     */
    function setApprovals() external {
        if (!this.approve(ROLLUP_PROCESSOR, type(uint256).max)) revert ErrorLib.ApproveFailed(address(this));
        if (!IERC20(LQTY).approve(ROLLUP_PROCESSOR, type(uint256).max)) revert ErrorLib.ApproveFailed(LQTY);
        if (!IERC20(LQTY).approve(address(STAKING_CONTRACT), type(uint256).max)) revert ErrorLib.ApproveFailed(LQTY);
        if (!IERC20(WETH).approve(address(UNI_ROUTER), type(uint256).max)) revert ErrorLib.ApproveFailed(WETH);
        if (!IERC20(LUSD).approve(address(UNI_ROUTER), type(uint256).max)) revert ErrorLib.ApproveFailed(LUSD);
        if (!IERC20(USDC).approve(address(UNI_ROUTER), type(uint256).max)) revert ErrorLib.ApproveFailed(USDC);
    }

    /**
     * @notice Function which stakes or unstakes LQTY to/from LQTYStaking.sol.
     * @dev This method can only be called from the RollupProcessor.sol. If the input asset is LQTY, staking flow is
     * executed. If SB, unstaking. RollupProcessor.sol has to transfer the tokens to the bridge before calling
     * the method. If this is not the case, the function will revert (either in STAKING_CONTRACT.stake(...) or during
     * SB burn).
     *
     * @param _inputAssetA - LQTY (Staking) or SB (Unstaking)
     * @param _outputAssetA - SB (Staking) or LQTY (Unstaking)
     * @param _totalInputValue - the amount of LQTY to stake or the amount of SB to burn and exchange for LQTY
     * @param _auxData - when set to 1 during withdrawals "urgent withdrawal mode" is set (see note bellow)
     * @return outputValueA - the amount of SB (Staking) or LQTY (Unstaking) minted/transferred to
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
    ) external payable override(BridgeBase) onlyRollup returns (uint256 outputValueA, uint256, bool) {
        if (_inputAssetA.erc20Address == LQTY && _outputAssetA.erc20Address == address(this)) {
            // Deposit
            // Stake and claim rewards
            STAKING_CONTRACT.stake(_totalInputValue);
            _swapRewardsToLQTYAndStake(false);
            uint256 totalSupply = totalSupply();
            // outputValueA = how much SB should be minted
            if (totalSupply == 0) {
                // When the totalSupply is 0, I set the SB/LQTY ratio to be 1.
                outputValueA = _totalInputValue;
            } else {
                uint256 totalLQTYOwnedBeforeDeposit = STAKING_CONTRACT.stakes(address(this)) - _totalInputValue;
                // totalSupply / totalLQTYOwnedBeforeDeposit = how much SB one LQTY is worth
                // When I multiply this ^ with the amount of LQTY deposited I get the amount of SB to be minted.
                outputValueA = (totalSupply * _totalInputValue) / totalLQTYOwnedBeforeDeposit;
            }
            _mint(address(this), outputValueA);
        } else if (_inputAssetA.erc20Address == address(this) && _outputAssetA.erc20Address == LQTY) {
            // Withdrawal
            // Claim rewards
            STAKING_CONTRACT.unstake(0);
            _swapRewardsToLQTYAndStake(_auxData == 1);

            // STAKING_CONTRACT.stakes(address(this)) / totalSupply() = how much LQTY is one SB
            // outputValueA = amount of LQTY to be withdrawn and sent to rollupProcessor
            outputValueA = (STAKING_CONTRACT.stakes(address(this)) * _totalInputValue) / totalSupply();
            STAKING_CONTRACT.unstake(outputValueA);
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
     * @notice Swaps any ETH and LUSD currently held by the contract to LQTY and stakes LQTY in LQTYStaking.sol.
     * @param _isUrgentWithdrawalMode When set to true the function doesn't revert when the swaps fail.
     * @dev Note: The best route for LUSD -> LQTY is consistently LUSD -> USDC -> WETH -> LQTY. Since I want to swap
     * liquidation rewards (ETH) to LQTY as well, I will first swap LUSD to WETH through USDC and then swap it all
     * to LQTY
     */
    function _swapRewardsToLQTYAndStake(bool _isUrgentWithdrawalMode) internal {
        uint256 lusdBalance = IERC20(LUSD).balanceOf(address(this));
        if (lusdBalance > MIN_LUSD_SWAP_AMT) {
            try UNI_ROUTER.exactInput(
                ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(LUSD, uint24(500), USDC, uint24(500), WETH),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: lusdBalance - DUST,
                    amountOutMinimum: 0
                })
            ) {} catch (bytes memory) {
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
            try UNI_ROUTER.exactInputSingle(
                ISwapRouter.ExactInputSingleParams(
                    WETH, LQTY, 3000, address(this), block.timestamp, wethBalance - DUST, 0, 0
                )
            ) returns (uint256 amountLQTYOut) {
                if (amountLQTYOut != 0) {
                    STAKING_CONTRACT.stake(amountLQTYOut);
                }
            } catch (bytes memory) {
                if (!_isUrgentWithdrawalMode) {
                    revert SwapFailed();
                }
            }
        }
    }
}
