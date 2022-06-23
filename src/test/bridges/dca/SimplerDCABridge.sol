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
        bridge.pokeNextTicks(8);

        bridge.deposit(0, 1000 ether, 8);
        bridge.deposit(1, 1000 ether, 8);

        emit log_named_uint("available", bridge.available());

        vm.warp(block.timestamp + 4 days);
        emit log_named_uint("available", bridge.available());
    }
}
