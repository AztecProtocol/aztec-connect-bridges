// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.8.0 <=0.8.10;
pragma abicoder v2;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "../../interfaces/IDefiBridge.sol";
import "../../interfaces/IWETH.sol";
import "./interfaces/ILQTYStaking.sol";
import "./interfaces/ISwapRouter.sol";

/**
 * @title Aztec Connect Bridge for Liquity's LQTYStaking.sol
 * @author Jan Benes (@benesjan on Github and Telegram)
 * @notice You can use this contract to stake and unstake LQRTY to and from LQTY staking contract.
 * @dev Implementation of the IDefiBridge interface for LQTYStaking.sol from Liquity protocol.
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
contract StakingBridge is IDefiBridge, ERC20("StakingBridge", "SB") {
    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant LQTY = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // set here because of multihop on Uni

    ILQTYStaking public constant STAKING_CONTRACT = ILQTYStaking(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d);
    ISwapRouter public constant UNI_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    address public immutable processor;

    /**
     * @notice Set the addresses of RollupProcessor.sol and token approvals.
     * @param _processor Address of the RollupProcessor.sol
     */
    constructor(address _processor) {
        processor = _processor;
    }

    /**
     * @notice Sets all the important approvals.
     * @dev StakingBridge never holds LUSD, LQTY, USDC or WETH after or before an invocation of any of its functions.
     * For this reason the following is not a security risk and makes the convert() function more gas efficient.
     */
    function setApprovals() public {
        require(this.approve(processor, type(uint256).max), "StakingBridge: SBB_APPROVE_FAILED");
        require(IERC20(LQTY).approve(processor, type(uint256).max), "StakingBridge: LUSD_APPROVE_FAILED");
        require(
            IERC20(LQTY).approve(address(STAKING_CONTRACT), type(uint256).max),
            "StakingBridge: LQTY_APPROVE_FAILED"
        );
        require(IERC20(WETH).approve(address(UNI_ROUTER), type(uint256).max), "StakingBridge: WETH_APPROVE_FAILED");
        require(IERC20(LUSD).approve(address(UNI_ROUTER), type(uint256).max), "StakingBridge: LUSD_APPROVE_FAILED");
        require(IERC20(USDC).approve(address(UNI_ROUTER), type(uint256).max), "StakingBridge: USDC_APPROVE_FAILED");
    }

    /**
     * @notice Function which stakes or unstakes LQTY to/from LQTYStaking.sol.
     * @dev This method can only be called from the RollupProcessor.sol. If the input asset is LQTY, staking flow is
     * executed. If SB, unstaking. RollupProcessor.sol has to transfer the tokens to the bridge before calling
     * the method. If this is not the case, the function will revert (either in STAKING_CONTRACT.stake(...) or during
     * SB burn).
     *
     * @param inputAssetA - LQTY (Staking) or SB (Unstaking)
     * @param outputAssetA - SB (Staking) or LQTY (Unstaking)
     * @param inputValue - the amount of LQTY to stake or the amount of SB to burn and exchange for LQTY
     * @return outputValueA - the amount of SB (Staking) or LQTY (Unstaking) minted/transferred to
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
        require(msg.sender == processor, "StakingBridge: INVALID_CALLER");

        if (inputAssetA.erc20Address == LQTY) {
            // Deposit
            require(outputAssetA.erc20Address == address(this), "StakingBridge: INCORRECT_DEPOSIT_INPUT");
            // Stake and claim rewards
            STAKING_CONTRACT.stake(inputValue);
            _swapRewardsToLQTYAndStake();
            // outputValueA = how much SB should be minted
            if (this.totalSupply() == 0) {
                // When the totalSupply is 0, I set the SB/LQTY ratio to be 1.
                outputValueA = inputValue;
            } else {
                uint256 totalLQTYOwnedBeforeDeposit = STAKING_CONTRACT.stakes(address(this)) - inputValue;
                // this.totalSupply() / totalLQTYOwnedBeforeDeposit = how much SB one LQTY is worth
                // When I multiply this ^ with the amount of LQTY deposited I get the amount of SB to be minted.
                outputValueA = (this.totalSupply() * inputValue) / totalLQTYOwnedBeforeDeposit;
            }
            _mint(address(this), outputValueA);
        } else {
            // Withdrawal
            require(
                inputAssetA.erc20Address == address(this) && outputAssetA.erc20Address == LQTY,
                "StakingBridge: INCORRECT_WITHDRAWAL_INPUT"
            );
            // Claim rewards
            STAKING_CONTRACT.unstake(0);
            _swapRewardsToLQTYAndStake();

            // STAKING_CONTRACT.stakes(address(this)) / this.totalSupply() = how much LQTY is one SB
            // outputValueA = amount of LQTY to be withdrawn and sent to rollupProcessor
            outputValueA = (STAKING_CONTRACT.stakes(address(this)) * inputValue) / this.totalSupply();
            STAKING_CONTRACT.unstake(outputValueA);
            _burn(address(this), inputValue);
        }
    }

    /*
     * @notice Swaps any ETH and LUSD currently held by the contract to LQTY and stakes LQTY in LQTYStaking.sol.
     *
     * @dev Note: The best route for LUSD -> LQTY is consistently LUSD -> USDC -> WETH -> LQTY. Since I want to swap
     * liquidation rewards (ETH) to LQTY as well, I will first swap LUSD to WETH through USDC and then swap it all
     * to LQTY
     */
    function _swapRewardsToLQTYAndStake() internal {
        uint256 lusdBalance = IERC20(LUSD).balanceOf(address(this));
        if (lusdBalance != 0) {
            uint256 usdcBalance = UNI_ROUTER.exactInputSingle(
                ISwapRouter.ExactInputSingleParams(LUSD, USDC, 500, address(this), block.timestamp, lusdBalance, 0, 0)
            );
            UNI_ROUTER.exactInputSingle(
                ISwapRouter.ExactInputSingleParams(USDC, WETH, 500, address(this), block.timestamp, usdcBalance, 0, 0)
            );
        }

        uint256 ethBalance = address(this).balance;
        if (ethBalance != 0) {
            // Wrap ETH in WETH
            IWETH(WETH).deposit{value: ethBalance}();
        }

        uint256 wethBalance = IERC20(WETH).balanceOf(address(this));
        if (wethBalance != 0) {
            uint256 amountLQTYOut = UNI_ROUTER.exactInputSingle(
                ISwapRouter.ExactInputSingleParams(WETH, LQTY, 3000, address(this), block.timestamp, wethBalance, 0, 0)
            );
            if (amountLQTYOut != 0) {
                STAKING_CONTRACT.stake(amountLQTYOut);
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
        require(false, "StakingBridge: ASYNC_MODE_DISABLED");
    }

    receive() external payable {}

    fallback() external payable {}
}
