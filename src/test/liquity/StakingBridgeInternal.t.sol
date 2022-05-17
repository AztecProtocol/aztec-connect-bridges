// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.0 <=0.8.10;
pragma abicoder v2;

import "./utils/TestUtil.sol";
import "../../bridges/liquity/StakingBridge.sol";

abstract contract StakingBridgeTestInternal is TestUtil, StakingBridge(address(0)) {

    function setUp() public {
        _aztecPreSetup();
        setUpTokens();
        require(IERC20(WETH).approve(address(UNI_ROUTER), type(uint256).max), "StakingBridge: WETH_APPROVE_FAILED");
        require(IERC20(LUSD).approve(address(UNI_ROUTER), type(uint256).max), "StakingBridge: LUSD_APPROVE_FAILED");
        require(IERC20(USDC).approve(address(UNI_ROUTER), type(uint256).max), "StakingBridge: USDC_APPROVE_FAILED");
    }

    function testSwapRewardsToLQTY() public {
        deal(tokens["LUSD"].addr, address(this), 1e21);

        // Note: to make the tests faster I will burn most of the ETH. This contract gets 79 million ETH by default.
        // This makes swapping through Uni v3 slow as it has the loop through the ticks for many seconds
        payable(address(0)).transfer(address(this).balance - 1 ether);

        uint256 stakedLQTYBeforeSwap = STAKING_CONTRACT.stakes(address(this));
        _swapRewardsToLQTYAndStake();
        uint256 stakedLQTYAfterSwap = STAKING_CONTRACT.stakes(address(this));

        // Verify that rewards were swapped for non-zero amount and correctly staked
        assertGt(stakedLQTYAfterSwap, stakedLQTYBeforeSwap);

        // Verify that all the rewards were swapped and staked
        assertEq(tokens["WETH"].erc.balanceOf(address(this)), 0);
        assertEq(tokens["LUSD"].erc.balanceOf(address(this)), 0);
        assertEq(tokens["LQTY"].erc.balanceOf(address(this)), 0);
        assertEq(address(this).balance, 0);
    }
}
