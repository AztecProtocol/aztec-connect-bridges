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
        //            500    3000    3000
        // PATH1 LUSD -> DAI -> WETH -> LQTY    30% of input 0011110 01 100 10 001 10
        //            500     3000    3000
        // PATH2 LUSD -> USDC -> WETH -> LQTY   70% of input 1000110 01 010 10 001 10
        // 0000000000000000000000000000000000000000000001111111 111111111111
        // 00000000000000000000000000 | 0011110 01 100 10 001 10 | 1000110 01 010 10 001 10
        uint64 encodedPath = 0xF32346546;
        SwapBridge.Path memory path = _decodePath(LUSD, encodedPath, LQTY);
    }

    function testDecodeSplitPathAllMiddleTokensUsed() public {
        bytes memory referencePath = abi.encodePacked(LUSD, uint24(500), USDC, uint24(3000), WETH, uint24(3000), LQTY);

        // 100 %   500 USDC 3000 WETH 3000
        // 1100100 01  010  10   001  10
        uint64 encodedPath = 0x64546;
        (uint256 percentage, bytes memory path) = _decodeSplitPath(LUSD, encodedPath, LQTY);
        assertEq(percentage, 100, "Incorrect percentage value");
        assertEq(string(path), string(referencePath), "Path incorrectly encoded");
    }

    function testDecodeSplitPathOneMiddleTokenUsed() public {
        bytes memory referencePath = abi.encodePacked(LUSD, uint24(500), USDC, uint24(3000), LQTY);

        // 70%     500 USDC 100  ---- 3000
        // 1000110 01  010  00   000  10
        uint64 encodedPath = 0x46502;
        (uint256 percentage, bytes memory path) = _decodeSplitPath(LUSD, encodedPath, LQTY);
        assertEq(percentage, 70, "Incorrect percentage value");
        assertEq(string(path), string(referencePath), "Path incorrectly encoded");
    }

    function testDecodeSplitPathNoMiddleTokenUsed() public {
        bytes memory referencePath = abi.encodePacked(LUSD, uint24(3000), LQTY);

        // 12%     100 ---  100  ---- 3000
        // 0001100 00  000  00   000  10
        uint64 encodedPath = 0xC002;
        (uint256 percentage, bytes memory path) = _decodeSplitPath(LUSD, encodedPath, LQTY);
        assertEq(percentage, 12, "Incorrect percentage value");
        assertEq(string(path), string(referencePath), "Path incorrectly encoded");
    }
}
