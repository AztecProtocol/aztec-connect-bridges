// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IDefiBridge} from "../../interfaces/IDefiBridge.sol";
import {AztecTypes} from "../../aztec/AztecTypes.sol";
import {IWETH} from "../../interfaces/IWETH.sol";

import {IStabilityPool} from "./interfaces/IStabilityPool.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";

/**
 * @title Aztec Connect Bridge for Liquity's StabilityPool.sol
 * @author Jan Benes (@benesjan on Github and Telegram)
 * @notice You can use this contract to deposit and withdraw LUSD to and from Liquity's StabilityPool.sol.
 * @dev Implementation of the IDefiBridge interface for StabilityPool.sol.
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
contract StabilityPoolBridge is IDefiBridge, ERC20("StabilityPoolBridge", "SPB") {
    error ApproveFailed(address token);
    error InvalidCaller();
    error IncorrectInput();
    error AsyncModeDisabled();

    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant LQTY = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // set here because of multihop on Uni

    IStabilityPool public constant STABILITY_POOL = IStabilityPool(0x66017D22b0f8556afDd19FC67041899Eb65a21bb);
    ISwapRouter public constant UNI_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    // The amount of dust to leave in the contract
    // Optimization based on EIP-1087
    uint256 internal constant DUST = 1;

    address public immutable ROLLUP_PROCESSOR;
    address public immutable FRONTEND_TAG; // see StabilityPool.sol for details

    /**
     * @notice Set the addresses of RollupProcessor.sol and front-end tag.
     * @param _rollupProcessor Address of the RollupProcessor.sol
     * @param _frontEndTag An address/tag identifying to which frontend LQTY frontend rewards should go. Can be zero.
     * @dev Frontend tag is set here because there can be only 1 frontend tag per msg.sender in the StabilityPool.sol.
     * See https://docs.liquity.org/faq/frontend-operators#how-do-frontend-tags-work[Liquity docs] for more details.
     */
    constructor(address _rollupProcessor, address _frontEndTag) {
        ROLLUP_PROCESSOR = _rollupProcessor;
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
        if (!this.approve(ROLLUP_PROCESSOR, type(uint256).max)) revert ApproveFailed(address(this));
        if (!IERC20(LUSD).approve(ROLLUP_PROCESSOR, type(uint256).max)) revert ApproveFailed(LUSD);
        if (!IERC20(LUSD).approve(address(STABILITY_POOL), type(uint256).max)) revert ApproveFailed(LUSD);
        if (!IERC20(WETH).approve(address(UNI_ROUTER), type(uint256).max)) revert ApproveFailed(WETH);
        if (!IERC20(LQTY).approve(address(UNI_ROUTER), type(uint256).max)) revert ApproveFailed(LQTY);
        if (!IERC20(USDC).approve(address(UNI_ROUTER), type(uint256).max)) revert ApproveFailed(USDC);
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
     * @param _inputValue - the amount of LUSD to deposit or the amount of SPB to burn and exchange for LUSD
     * @return outputValueA - the amount of SPB (Deposit) or LUSD (Withdrawal) minted/transferred to
     * the RollupProcessor.sol
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _inputValue,
        uint256,
        uint64,
        address
    )
        external
        payable
        override(IDefiBridge)
        returns (
            uint256 outputValueA,
            uint256,
            bool
        )
    {
        if (msg.sender != ROLLUP_PROCESSOR) revert InvalidCaller();

        if (_inputAssetA.erc20Address == LUSD && _outputAssetA.erc20Address == address(this)) {
            // Deposit
            // Provides LUSD to the pool and claim rewards.
            STABILITY_POOL.provideToSP(_inputValue, FRONTEND_TAG);
            _swapRewardsToLUSDAndDeposit();
            uint256 totalLUSDOwnedBeforeDeposit = STABILITY_POOL.getCompoundedLUSDDeposit(address(this)) - _inputValue;
            uint256 totalSupply = this.totalSupply();
            // outputValueA = how much SPB should be minted
            if (totalSupply == 0) {
                // When the totalSupply is 0, I set the SPB/LUSD ratio to be 1.
                outputValueA = _inputValue;
            } else {
                // totalSupply / totalLUSDOwnedBeforeDeposit = how much SPB one LUSD is worth
                // When I multiply this ^ with the amount of LUSD deposited I get the amount of SPB to be minted.
                outputValueA = (totalSupply * _inputValue) / totalLUSDOwnedBeforeDeposit;
            }
            _mint(address(this), outputValueA);
        } else if (_inputAssetA.erc20Address == address(this) && _outputAssetA.erc20Address == LUSD) {
            // Withdrawal
            // Claim rewards and swap them to LUSD.
            STABILITY_POOL.withdrawFromSP(0);
            _swapRewardsToLUSDAndDeposit();

            // stabilityPool.getCompoundedLUSDDeposit(address(this)) / this.totalSupply() = how much LUSD is one SPB
            // outputValueA = amount of LUSD to be withdrawn and sent to RollupProcessor.sol
            outputValueA = (STABILITY_POOL.getCompoundedLUSDDeposit(address(this)) * _inputValue) / this.totalSupply();
            STABILITY_POOL.withdrawFromSP(outputValueA);
            _burn(address(this), _inputValue);
        } else {
            revert IncorrectInput();
        }
    }

    // @notice This function always reverts because this contract does not implement async flow.
    function finalise(
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        uint256,
        uint64
    )
        external
        payable
        override(IDefiBridge)
        returns (
            uint256,
            uint256,
            bool
        )
    {
        revert AsyncModeDisabled();
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view override(ERC20) returns (uint256) {
        return super.totalSupply() - DUST;
    }

    /*
     * @notice Swaps any ETH and LQTY currently held by the contract to LUSD and deposits LUSD to the StabilityPool.sol.
     *
     * @dev Note: The best route for LQTY -> LUSD is consistently LQTY -> WETH -> USDC -> LUSD. Since I want to swap
     * liquidations rewards (ETH) to LUSD as well, I will first swap LQTY to WETH and then swap it all through USDC to
     * LUSD.
     */
    function _swapRewardsToLUSDAndDeposit() internal {
        uint256 lqtyBalance = IERC20(LQTY).balanceOf(address(this));
        if (lqtyBalance > DUST) {
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
            );
        }

        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            // Wrap ETH in WETH
            IWETH(WETH).deposit{value: ethBalance}();
        }

        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        if (wethBalance > DUST) {
            uint256 lusdBalance = UNI_ROUTER.exactInput(
                ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(WETH, uint24(500), USDC, uint24(500), LUSD),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: wethBalance - DUST,
                    amountOutMinimum: 0
                })
            );

            if (lusdBalance != 0) {
                STABILITY_POOL.provideToSP(lusdBalance, FRONTEND_TAG);
            }
        }
    }
}
