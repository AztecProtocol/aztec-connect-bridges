// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {TestUtil} from "./utils/TestUtil.sol";
import {TroveBridge} from "../../bridges/liquity/TroveBridge.sol";

contract TroveBridgeTestInternal is TestUtil, TroveBridge(address(0), 160) {
    function setUp() public {
        setUpTokens();
        require(IERC20(LUSD).approve(address(UNI_ROUTER), type(uint256).max), "LUSD_APPROVE_FAILED");
    }

    function testSwapEthToLusd() public {
        uint256 ethAmount = 1 ether;
        uint256 lusdAmount = 5e19; // 50 LUSD

        // Note: to make the tests faster I will burn most of the ETH. This contract gets 79 million ETH by default.
        // This makes swapping through Uni v3 slow as it has to loop through the ticks for many seconds
        payable(address(0)).transfer(address(this).balance - ethAmount);
        assertEq(address(this).balance, ethAmount, "Balance doesn't equal 1 ether");

        _swapEthToLusd(lusdAmount); // Try to swap and get 5 LUSD out

        assertEq(
            tokens["LUSD"].erc.balanceOf(address(this)),
            lusdAmount,
            "LUSD received doesn't equal the required amount"
        );
        assertGt(address(this).balance, 95e16, "Uniswap took too much ETH for the required LUSD amount");
    }
}
