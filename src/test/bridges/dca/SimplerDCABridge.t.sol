// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ICERC20} from "../../../interfaces/compound/ICERC20.sol";
import {SimplerDCABridge} from "../../../bridges/dca/SimplerDCABridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

contract SimplerDCATest is Test {
    SimplerDCABridge internal bridge;

    function setUp() public {
        bridge = new SimplerDCABridge(address(this));
    }

    function testSmallFlow() public {
        emit log("START");
        bridge.pokeNextTicks(30);

        bridge.deposit(0, 300 ether, 3);
        vm.warp(block.timestamp + 1 days);
        bridge.deposit(1, 700 ether, 7);
        bridge.deposit(2, 14000 ether, 14);

        emit log_named_decimal_uint("available", bridge.available(), 18);

        vm.warp(block.timestamp + 1 days);
        emit log_named_decimal_uint("available", bridge.available(), 18);

        uint256 start = bridge.lastTickBought();

        for (uint256 i = start; i < start + 8; i++) {
            SimplerDCABridge.Tick memory tick = bridge.getTick(i);
            emit log_named_uint("tick", i);
            emit log_named_decimal_uint("avail  ", tick.available, 18);
            emit log_named_decimal_uint("sold   ", tick.sold, 18);
            emit log_named_decimal_uint("bought ", tick.bought, 18);
        }
        emit log("---");

        {
            (uint256 bought, uint256 sold, uint256 refund) = bridge.trade(5 ether);

            emit log_named_decimal_uint("bought", bought, 18);
            emit log_named_decimal_uint("sold", sold, 18);
            emit log_named_decimal_uint("refund", refund, 18);

            for (uint256 i = start; i < start + 8; i++) {
                SimplerDCABridge.Tick memory tick = bridge.getTick(i);
                emit log_named_uint("tick", i);
                emit log_named_decimal_uint("avail  ", tick.available, 18);
                emit log_named_decimal_uint("sold   ", tick.sold, 18);
                emit log_named_decimal_uint("bought ", tick.bought, 18);
            }
        }
        emit log("---");
        {
            (uint256 bought, uint256 sold, uint256 refund) = bridge.trade(5 ether);

            emit log_named_decimal_uint("bought", bought, 18);
            emit log_named_decimal_uint("sold", sold, 18);
            emit log_named_decimal_uint("refund", refund, 18);

            for (uint256 i = start; i < start + 8; i++) {
                SimplerDCABridge.Tick memory tick = bridge.getTick(i);
                emit log_named_uint("tick", i);
                emit log_named_decimal_uint("avail  ", tick.available, 18);
                emit log_named_decimal_uint("sold   ", tick.sold, 18);
                emit log_named_decimal_uint("bought ", tick.bought, 18);
            }
        }
        for (uint256 i = 0; i < 2; i++) {
            (uint256 accumulated, bool ready) = bridge.getAccumulated(i);
            emit log_named_decimal_uint("accumulated", accumulated, 18);
            if (ready) {
                emit log("Ready for harvest");
            } else {
                emit log("Not ready");
            }
        }
        vm.warp(block.timestamp + 10 days);
        (uint256 bought, uint256 sold, uint256 refund) = bridge.trade(30 ether);

        for (uint256 i = 0; i < 3; i++) {
            (uint256 accumulated, bool ready) = bridge.getAccumulated(i);
            emit log_named_decimal_uint("accumulated", accumulated, 18);
            if (ready) {
                emit log("Ready for harvest");
            } else {
                emit log("Not ready");
            }
        }
    }
}
