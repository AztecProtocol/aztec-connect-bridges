// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TestUtil} from "./utils/TestUtil.sol";
import {StabilityPoolBridge} from "../../bridges/liquity/StabilityPoolBridge.sol";

abstract contract StabilityPoolBridgeTestInternal is TestUtil, StabilityPoolBridge(address(0), address(0)) {
    function setUp() public {
        _aztecPreSetup();
        setUpTokens();

        require(IERC20(WETH).approve(address(UNI_ROUTER), type(uint256).max), "WETH_APPROVE_FAILED");
        require(IERC20(LQTY).approve(address(UNI_ROUTER), type(uint256).max), "LQTY_APPROVE_FAILED");
        require(IERC20(USDC).approve(address(UNI_ROUTER), type(uint256).max), "USDC_APPROVE_FAILED");
    }

    function testSwapRewardsOnUni() public {
        deal(tokens["LQTY"].addr, address(this), 1e21);

        // Note: to make the tests faster I will burn most of the ETH. This contract gets 79 million ETH by default.
        // This makes swapping through Uni v3 slow as it has the loop through the ticks for many seconds
        payable(address(0)).transfer(address(this).balance - 1 ether);

        uint256 depositedLUSDBeforeSwap = STABILITY_POOL.getCompoundedLUSDDeposit(address(this));
        swapRewardsToLUSDAndDeposit();
        uint256 depositedLUSDAfterSwap = STABILITY_POOL.getCompoundedLUSDDeposit(address(this));

        // Verify that rewards were swapped for non-zero amount and correctly staked
        assertGt(depositedLUSDAfterSwap, depositedLUSDBeforeSwap);

        // Verify that all the rewards were swapped to LUSD
        assertEq(tokens["WETH"].erc.balanceOf(address(this)), 0);
        assertEq(tokens["LQTY"].erc.balanceOf(address(this)), 0);
        assertEq(tokens["LUSD"].erc.balanceOf(address(this)), 0);
        assertEq(address(this).balance, 0);
    }
}
