// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TestUtil} from "./utils/TestUtil.sol";
import {StabilityPoolBridge} from "../../../bridges/liquity/StabilityPoolBridge.sol";

contract StabilityPoolBridgeTestInternal is TestUtil, StabilityPoolBridge(address(0), address(0)) {
    address public constant LQTY_ETH_POOL = 0xD1D5A4c0eA98971894772Dcd6D2f1dc71083C44E; // 3000 bps fee tier
    address public constant USDC_ETH_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640; // 500 bps fee tier
    address public constant LUSD_USDC_POOL = 0x4e0924d3a751bE199C426d52fb1f2337fa96f736; // 500 bps fee tier

    function setUp() public {
        rollupProcessor = address(this);
        setUpTokens();

        // solhint-disable-next-line
        require(IERC20(WETH).approve(address(UNI_ROUTER), type(uint256).max), "WETH_APPROVE_FAILED");
        // solhint-disable-next-line
        require(IERC20(LQTY).approve(address(UNI_ROUTER), type(uint256).max), "LQTY_APPROVE_FAILED");
        // solhint-disable-next-line
        require(IERC20(USDC).approve(address(UNI_ROUTER), type(uint256).max), "USDC_APPROVE_FAILED");

        // EIP-1087 optimization related mints
        deal(tokens["LQTY"].addr, address(this), 1);
        deal(tokens["LUSD"].addr, address(this), 1);
        deal(tokens["WETH"].addr, address(this), 1);
    }

    function testSwapRewardsOnUni() public {
        deal(tokens["LQTY"].addr, address(this), 1e21);

        // Note: to make the tests faster I will burn most of the ETH. This contract gets 79 million ETH by default.
        // This makes swapping through Uni v3 slow as it has to loop through the ticks for many seconds
        payable(address(0)).transfer(address(this).balance - 1 ether);

        uint256 depositedLUSDBeforeSwap = STABILITY_POOL.getCompoundedLUSDDeposit(address(this));
        _swapRewardsToLUSDAndDeposit(false);
        uint256 depositedLUSDAfterSwap = STABILITY_POOL.getCompoundedLUSDDeposit(address(this));

        // Verify that rewards were swapped for non-zero amount and correctly staked
        assertGt(depositedLUSDAfterSwap, depositedLUSDBeforeSwap);

        // Verify that all the rewards were swapped to LUSD
        assertEq(tokens["WETH"].erc.balanceOf(address(this)), DUST);
        assertEq(tokens["LQTY"].erc.balanceOf(address(this)), DUST);
        assertEq(tokens["LUSD"].erc.balanceOf(address(this)), DUST);
        assertEq(address(this).balance, 0);
    }

    function testUrgentModeOnSwap1() public {
        // Destroy the pools reserves in order for the swap to fail
        deal(WETH, LQTY_ETH_POOL, 0);
        deal(LQTY, address(this), 1e21);

        // Call shouldn't revert even though swap 1 fails
        _swapRewardsToLUSDAndDeposit(true);
    }

    function testUrgentModeOnSwap2() public {
        // Destroy the pools reserves in order for the swap to fail
        deal(USDC, USDC_ETH_POOL, 0);
        deal(LQTY, address(this), 1e21);

        // Call shouldn't revert even though swap 1 fails
        _swapRewardsToLUSDAndDeposit(true);
    }

    function testUrgentModeOnSwap3() public {
        // Destroy the pools reserves in order for the swap to fail
        deal(LUSD, LUSD_USDC_POOL, 0);
        deal(LQTY, address(this), 1e21);

        // Call shouldn't revert even though swap 1 fails
        _swapRewardsToLUSDAndDeposit(true);
    }
}
