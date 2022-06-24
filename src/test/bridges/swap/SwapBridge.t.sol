// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ExampleBridgeContract} from "../../../bridges/example/ExampleBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {SwapBridge} from "../../../bridges/swap/SwapBridge.sol";

contract SwapBridgeTest is BridgeTestBase {
    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    // The reference to the example bridge
    SwapBridge internal bridge;

    // To store the id of the swap bridge after being added
    uint256 private id;

    function setUp() public {
        // Deploy a new example bridge
        bridge = new SwapBridge(address(ROLLUP_PROCESSOR));

        // use the label cheatcode to mark the address with "Example Bridge" in the traces
        vm.label(address(bridge), "Swap Bridge");

        // Impersonate the multi-sig to add a new bridge
        vm.prank(MULTI_SIG);

        // List the example-bridge with a gasLimit of 100K
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 100000);

        // Fetch the id of the example bridge
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();
    }

    //    function testInvalidInputAssetType() public {
    //        vm.prank(address(ROLLUP_PROCESSOR));
    //        vm.expectRevert(ErrorLib.InvalidInputA.selector);
    //        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    //    }

    function testByteShift() public {
        uint16 a = 397; // equals 0110001101 in binary

        // Read bits at positions 3 and 7.
        // Note that bits are 0-indexed, thus bit 1 is at position 0, bit 2 is at position 1, etc.
        uint16 bit3 = a & (1 << 2);
        uint256 l = 1 << 4;
        //        uint8 bit7 = a & (1 << 6);
        emit log_uint(l);
    }

    // @notice The purpose of this test is to directly test convert functionality of the bridge.
    // @dev In order to avoid overflows we set _depositAmount to be uint96 instead of uint256.
    function testSwapBridgeUnitTest() public {
        uint256 _swapAmount = 1e21;

        // Define input and output assets
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(DAI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 0,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.ETH
        });

        bridge.convert(inputAssetA, emptyAsset, outputAssetA, emptyAsset, _swapAmount, 0, uint64(246), address(0));
    }
}
