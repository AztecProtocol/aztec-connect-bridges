// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {StakingBridge} from "../../../bridges/liquity/StakingBridge.sol";
import {TestUtil} from "./utils/TestUtil.sol";

contract StakingBridgeTestInternal is TestUtil, StakingBridge(address(0)) {
    function setUp() public {
        _setUpTokensAndLabels();
        rollupProcessor = address(this);

        // solhint-disable-next-line
        require(IERC20(WETH).approve(address(UNI_ROUTER), type(uint256).max), "WETH_APPROVE_FAILED");
        // solhint-disable-next-line
        require(IERC20(LUSD).approve(address(UNI_ROUTER), type(uint256).max), "LUSD_APPROVE_FAILED");
        // solhint-disable-next-line
        require(IERC20(USDC).approve(address(UNI_ROUTER), type(uint256).max), "USDC_APPROVE_FAILED");

        // EIP-1087 optimization related mints
        deal(tokens["LUSD"].addr, address(this), 1);
        deal(tokens["LQTY"].addr, address(this), 1);
        deal(tokens["WETH"].addr, address(this), 1);
    }

    function testSwapRewardsToLQTY() public {
        deal(tokens["LUSD"].addr, address(this), 1e21);

        // Note: to make the tests faster I will burn most of the ETH. This contract gets 79 million ETH by default.
        // This makes swapping through Uni v3 slow as it has to loop through the ticks for many seconds
        payable(address(0)).transfer(address(this).balance - 1 ether);

        uint256 stakedLQTYBeforeSwap = STAKING_CONTRACT.stakes(address(this));
        _swapRewardsToLQTYAndStake(false);
        uint256 stakedLQTYAfterSwap = STAKING_CONTRACT.stakes(address(this));

        // Verify that rewards were swapped for non-zero amount and correctly staked
        assertGt(stakedLQTYAfterSwap, stakedLQTYBeforeSwap);

        // Verify that all the rewards were swapped and staked
        assertEq(tokens["WETH"].erc.balanceOf(address(this)), DUST);
        assertEq(tokens["LUSD"].erc.balanceOf(address(this)), DUST);
        assertEq(tokens["LQTY"].erc.balanceOf(address(this)), DUST);
        assertEq(address(this).balance, 0);
    }

    function testUrgentModeOnSwap1() public {
        // Destroy the pools reserves in order for the swap to fail
        deal(USDC, LUSD_USDC_POOL, 0);
        deal(LUSD, address(this), 1e21);

        // Call shouldn't revert even though the swap fails
        _swapRewardsToLQTYAndStake(true);
    }

    function testUrgentModeOnSwap2() public {
        // Destroy the pools reserves in order for the swap to fail
        deal(WETH, USDC_ETH_POOL, 0);
        deal(LUSD, address(this), 1e21);

        // Call shouldn't revert even though the swap fails
        _swapRewardsToLQTYAndStake(true);
    }

    function testUrgentModeOnSwap3() public {
        // Destroy the pools reserves in order for the swap to fail
        deal(LQTY, LQTY_ETH_POOL, 0);
        deal(LUSD, address(this), 1e21);

        // Call shouldn't revert even though the swap fails
        _swapRewardsToLQTYAndStake(true);
    }
}
