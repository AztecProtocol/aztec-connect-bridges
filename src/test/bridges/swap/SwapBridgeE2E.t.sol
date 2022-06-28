// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {SwapBridge} from "../../../bridges/swap/SwapBridge.sol";

contract SwapBridgeE2ETest is BridgeTestBase {
    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant LQTY = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    SwapBridge private bridge;

    // To store the id of the swap bridge after being added
    uint256 private id;

    function setUp() public {
        // Deploy the bridge
        bridge = new SwapBridge(address(ROLLUP_PROCESSOR));

        // Use the label cheatcode to mark addresses in the traces
        vm.label(address(bridge), "Swap Bridge");
        vm.label(address(bridge.UNI_ROUTER()), "Uni Router");
        vm.label(LUSD, "LUSD");
        vm.label(DAI, "DAI");
        vm.label(WETH, "WETH");
        vm.label(LQTY, "LQTY");
        vm.label(USDC, "USDC");

        // Impersonate the multi-sig to add a new bridge
        vm.prank(MULTI_SIG);

        // List the example-bridge with a gasLimit of 100K
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 100000);

        // Fetch the id of the example bridge
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();
    }

    function testSwap() public {
        // TODO
    }
}
