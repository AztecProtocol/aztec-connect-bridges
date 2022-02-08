// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.8.0 <=0.8.10;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../interfaces/IDefiBridge.sol";
import "../../interfaces/IWETH.sol";
import "./interfaces/IStabilityPool.sol";
import "./interfaces/ISwapRouter.sol";

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
    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant LQTY = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // set here because of multihop on Uni

    IStabilityPool public constant STABILITY_POOL = IStabilityPool(0x66017D22b0f8556afDd19FC67041899Eb65a21bb);
    ISwapRouter public constant UNI_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    address public immutable processor;
    address public immutable frontEndTag; // see StabilityPool.sol for details

    /**
     * @notice Set addresses and token approvals.
     * @param _processor Address of the RollupProcessor.sol
     * @param _frontEndTag An address/tag identifying to which frontend LQTY frontend rewards should go. Can be zero.
     * @dev Frontend tag is set here because there can be only 1 frontend tag per msg.sender in the StabilityPool.sol.
     * See https://docs.liquity.org/faq/frontend-operators#how-do-frontend-tags-work[Liquity docs] for more details.
     */
    constructor(address _processor, address _frontEndTag) {
        processor = _processor;
        frontEndTag = _frontEndTag;
    }

    /**
     * @notice Sets all the important approvals.
     * @dev StabilityPoolBridge never holds LUSD, LQTY, USDC or WETH after or before an invocation of any of its
     * functions. For this reason the following is not a security risk and makes the convert() function more gas
     * efficient.
     */
    function setApprovals() public {
        require(this.approve(processor, type(uint256).max), "StabilityPoolBridge: SPB_APPROVE_FAILED");
        require(IERC20(LUSD).approve(processor, type(uint256).max), "StabilityPoolBridge: LUSD_APPROVE_FAILED");
        require(
            IERC20(LUSD).approve(address(STABILITY_POOL), type(uint256).max),
            "StabilityPoolBridge: LUSD_APPROVE_FAILED"
        );
        require(
            IERC20(WETH).approve(address(UNI_ROUTER), type(uint256).max),
            "StabilityPoolBridge: WETH_APPROVE_FAILED"
        );
        require(
            IERC20(LQTY).approve(address(UNI_ROUTER), type(uint256).max),
            "StabilityPoolBridge: LQTY_APPROVE_FAILED"
        );
        require(
            IERC20(USDC).approve(address(UNI_ROUTER), type(uint256).max),
            "StabilityPoolBridge: USDC_APPROVE_FAILED"
        );
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
     * @param inputAssetA - LUSD (Deposit) or SPB (Withdrawal)
     * @param outputAssetA - SPB (Deposit) or LUSD (Withdrawal)
     * @param inputValue - the amount of LUSD to deposit or the amount of SPB to burn and exchange for LUSD
     * @return outputValueA - the amount of SPB (Deposit) or LUSD (Withdrawal) minted/transferred to
     * the RollupProcessor.sol
     */
    function convert(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 inputValue,
        uint256,
        uint64
    )
        external
        payable
        override
        returns (
            uint256 outputValueA,
            uint256,
            bool isAsync
        )
    {
        require(msg.sender == processor, "StabilityPoolBridge: INVALID_CALLER");
        isAsync = false;

        if (inputAssetA.erc20Address == LUSD) {
            // Deposit
            require(outputAssetA.erc20Address == address(this), "StabilityPoolBridge: INCORRECT_DEPOSIT_INPUT");
            // Deposit LUSD and claim rewards.
            STABILITY_POOL.provideToSP(inputValue, frontEndTag);
            _swapRewardsToLUSDAndDeposit();
            uint256 totalLUSDOwnedBeforeDeposit = STABILITY_POOL.getCompoundedLUSDDeposit(address(this)) - inputValue;
            // outputValueA = how much SPB should be minted
            if (this.totalSupply() == 0) {
                // When the totalSupply is 0, I set the SPB/LUSD ratio to be 1.
                outputValueA = inputValue;
            } else {
                // this.totalSupply() / totalLUSDOwnedBeforeDeposit = how much SPB one LUSD is worth
                // When I multiply this ^ with the amount of LUSD deposited I get the amount of SPB to be minted.
                outputValueA = (this.totalSupply() * inputValue) / totalLUSDOwnedBeforeDeposit;
            }
            _mint(address(this), outputValueA);
        } else {
            // Withdrawal
            require(
                inputAssetA.erc20Address == address(this) && outputAssetA.erc20Address == LUSD,
                "StabilityPoolBridge: INCORRECT_WITHDRAWAL_INPUT"
            );
            // Claim rewards and swap them to LUSD.
            STABILITY_POOL.withdrawFromSP(0);
            _swapRewardsToLUSDAndDeposit();

            // stabilityPool.getCompoundedLUSDDeposit(address(this)) / this.totalSupply() = how much LUSD is one SPB
            // outputValueA = amount of LUSD to be withdrawn and sent to RollupProcessor.sol
            outputValueA = (STABILITY_POOL.getCompoundedLUSDDeposit(address(this)) * inputValue) / this.totalSupply();
            STABILITY_POOL.withdrawFromSP(outputValueA);
            _burn(address(this), inputValue);
        }
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
        if (lqtyBalance != 0) {
            UNI_ROUTER.exactInputSingle(
                ISwapRouter.ExactInputSingleParams(LQTY, WETH, 3000, address(this), block.timestamp, lqtyBalance, 0, 0)
            );
        }

        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            // Wrap ETH in WETH
            IWETH(WETH).deposit{value: ethBalance}();
        }

        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        if (wethBalance != 0) {
            uint256 usdcBalance = UNI_ROUTER.exactInputSingle(
                ISwapRouter.ExactInputSingleParams(WETH, USDC, 500, address(this), block.timestamp, wethBalance, 0, 0)
            );
            uint256 lusdBalance = UNI_ROUTER.exactInputSingle(
                ISwapRouter.ExactInputSingleParams(USDC, LUSD, 500, address(this), block.timestamp, usdcBalance, 0, 0)
            );
            if (lusdBalance != 0) {
                STABILITY_POOL.provideToSP(lusdBalance, frontEndTag);
            }
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
        override
        returns (
            uint256,
            uint256,
            bool
        )
    {
        require(false, "StabilityPoolBridge: ASYNC_MODE_DISABLED");
    }
}
