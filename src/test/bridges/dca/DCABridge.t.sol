// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ICERC20} from "../../../interfaces/compound/ICERC20.sol";
import {DCABridge} from "../../../bridges/dca/DCABridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

contract DCATest is Test {
    DCABridge internal bridge;

    function setUp() public {
        bridge = new DCABridge(address(this));
    }

    function testSmallFlow() public {
        emit log_named_uint("snap epoch", bridge.epoch());
        emit log_named_uint("sell epoch", bridge.epochLastSell());

        emit log("##### Initial");
        _printPoint(bridge.epoch());

        emit log("##### Deposit");
        bridge.deposit(0, 1000 ether, block.timestamp + 7 days);
        _printDCA(uint256(0));
        _printPoint(bridge.epoch());

        emit log_named_uint("cansell", bridge.canSell());
        emit log_named_uint("snap epoch", bridge.epoch());
        emit log_named_uint("sell epoch", bridge.epochLastSell());

        emit log("##### Deposit");
        vm.warp(block.timestamp + 3600);
        bridge.deposit(1, 1000 ether, block.timestamp + 7 days);
        // Would we also mess it up just directly with a checkpoint
        _printDCA(uint256(1));
        _printPoint(bridge.epoch());

        // The problem could be that we are not updating a new one? The accumulator is too big in the first go?

        emit log_named_uint("cansell", bridge.canSell());
        emit log_named_uint("snap epoch", bridge.epoch());
        emit log_named_uint("sell epoch", bridge.epochLastSell());

        emit log("##### Swap");
        bridge.performSwap();

        _printPoint(bridge.epoch());

        emit log_named_uint("cansell", bridge.canSell());
        emit log_named_uint("snap epoch", bridge.epoch());
        emit log_named_uint("sell epoch", bridge.epochLastSell());

        emit log("##### warp + second deposit");
        vm.warp(block.timestamp + 2 days);
        // Why does it get worse the higher this is
        bridge.checkPoint();
        bridge.deposit(2, 1000000000 ether, block.timestamp + 7 days);
        vm.warp(block.timestamp + 1000);
        bridge.deposit(3, 1000 ether, block.timestamp + 7 days);

        _printDCA(uint256(2));

        _printPoint(bridge.epoch());

        emit log_named_uint("cansell", bridge.canSell());
        emit log_named_uint("snap epoch", bridge.epoch());
        emit log_named_uint("sell epoch", bridge.epochLastSell());

        emit log("##### Sell everything");
        uint256 endTime = bridge.getDCA(2).endTime;
        vm.warp(endTime + 1);
        bridge.performSwap();

        for (uint256 i = 0; i <= bridge.epoch(); i++) {
            //_printPoint(i);
        }
        emit log_named_uint("cansell", bridge.canSell());
        emit log_named_uint("snap epoch", bridge.epoch());
        emit log_named_uint("sell epoch", bridge.epochLastSell());

        emit log_named_uint("timestamp", block.timestamp);

        // Ok how much should we have earned from this?
        for (uint256 i = 0; i < 4; i++) {
            _printDCA(i);
            DCABridge.DCA memory dca = bridge.getDCA(i);
            uint256 real = bridge.ethAccumulated(i);
            uint256 expected = (dca.amount * bridge.getPrice()) / 1e18;
            emit log_named_decimal_uint("eth  ", real, 18);
            emit log_named_decimal_uint("ideal", expected, 18);
            emit log_named_decimal_uint("ratio", (real * 10000) / expected, 4);
            assertLe(real, expected, "FUCK");
        }

        emit log_named_decimal_uint("dust", bridge.dust(), 18);

        // Ok, something is wrong with the accumulators. Or at least the first accumulator might be a little too big or what?
    }

    function _printPoint(uint256 _epoch) internal {
        DCABridge.Point memory p = bridge.getHistory(_epoch);
        emit log("---");
        emit log_named_uint("History at ", _epoch);
        emit log_named_int(" bias  ", p.bias);
        emit log_named_int(" slope ", p.slope);
        emit log_named_uint(" ts    ", p.ts);
        emit log_named_decimal_uint(" avail ", p.available, 18);
        emit log_named_decimal_uint(" bought", p.bought, 18);
    }

    function _printDCA(uint256 _nonce) internal {
        DCABridge.DCA memory dca = bridge.getDCA(_nonce);
        emit log_named_uint("DCA at   ", _nonce);
        emit log_named_uint(" amount   ", dca.amount);
        emit log_named_uint(" slope    ", dca.slope);
        emit log_named_uint("startEpoch", dca.startEpoch);
        emit log_named_uint(" endTime  ", dca.endTime);
    }

    function _printChange(uint256 _ts) internal {
        int256 c = bridge.changes(_ts);
        emit log_named_uint("Changes at ", _ts);
        emit log_named_int(" slope ", c);
    }
}
