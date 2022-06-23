// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {DSTest} from "ds-test/test.sol";
import {SwapBridge} from "../../../bridges/swap/SwapBridge.sol";

contract SwapBridgeInternalTest is DSTest, SwapBridge(address(0)) {
    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant LQTY = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function setUp() public {}

    function testDecodePath() public {
        //            500      3000      3000
        // PATH LUSD  ->  USDC  ->  WETH  ->  LQTY
        // 0000000000000000000000000000000000000000000001111111111111111111
        // 0000000000000000000000000000000000000000000001111111 01 010 10 001 10
        uint64 encodedPath = 0x7F546;
        _decodePath(LUSD, encodedPath, LQTY);
    }
}
