// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../../lib/rollup-encoder/src/libraries/AztecTypes.sol";

// Example-specific imports
import {AddressRegistry} from "../../../bridges/registry/AddressRegistry.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

/**
 * @notice The purpose of this test is to test the bridge in an environment that is as close to the final deployment
 *         as possible without spinning up all the rollup infrastructure (sequencer, proof generator etc.).
 */
contract AddressRegistryE2ETest is BridgeTestBase {
    // address private constant BENEFICIARY = address(11);

    // The reference to the example bridge
    AddressRegistry internal bridge;
    // To store the id of the example bridge after being added
    uint256 private id;
    AztecTypes.AztecAsset private ethAsset;
    AztecTypes.AztecAsset private virtualAsset1;
    uint256 public maxInt = type(uint160).max;
    event log(string, uint);
    event logAddress(address);

    function setUp() public {
        // Deploy a new example bridge
        bridge = new AddressRegistry(address(ROLLUP_PROCESSOR));
        ethAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        // Define input and output assets
        virtualAsset1 = AztecTypes.AztecAsset({
            id: 0,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.VIRTUAL
        });

        // Use the label cheatcode to mark the address with "Example Bridge" in the traces
        vm.label(address(bridge), "Address Registry Bridge");

        // Impersonate the multi-sig to add a new bridge
        vm.startPrank(MULTI_SIG);

        // List the example-bridge with a gasLimit of 120k
        // WARNING: If you set this value too low the interaction will fail for seemingly no reason!
        // OTOH if you se it too high bridge users will pay too much
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 1200000);

        vm.stopPrank();

        // Fetch the id of the example bridge
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();
    }

    function testGetVirtualAssets() public {
        vm.warp(block.timestamp + 1 days);

        // Computes the encoded data for the specific bridge interaction
        // uint256 bridgeCallData =
        ROLLUP_ENCODER.defiInteractionL2(
            id,
            ethAsset,
            emptyAsset,
            virtualAsset1,
            emptyAsset,
            0,
            1
        );

        // bytes memory err = abi.encodePacked(ErrorLib.InvalidAuxData.selector);

        // ROLLUP_ENCODER.registerEventToBeChecked(
        //     bridgeCallData,
        //     ROLLUP_ENCODER.getNextNonce(),
        //     0,
        //     maxInt,
        //     0,
        //     true,
        //     err
        // );

        // Execute the rollup with the bridge interaction. Ensure that event as seen above is emitted.
        (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        ) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        // Check the output values are as expected
        assertEq(outputValueA, maxInt, "outputValueA doesn't equal maxInt");
        assertEq(outputValueB, 0, "Non-zero outputValueB");
        assertFalse(isAsync, "Bridge is not synchronous");
    }

    function testRegistration() public {
        uint160 inputAmount = uint160(
            0x2e782B05290A7fFfA137a81a2bad2446AD0DdFEA
        );

        ROLLUP_ENCODER.defiInteractionL2(
            id,
            virtualAsset1,
            emptyAsset,
            virtualAsset1,
            emptyAsset,
            0,
            inputAmount
        );

        // Execute the rollup with the bridge interaction. Ensure that event as seen above is emitted.
        (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        ) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        uint64 addressId = bridge.id();
        uint64 registeredId = addressId - 1;
        address newlyRegistered = bridge.addresses(registeredId);

        // Check the output values are as expected
        assertEq(
            address(inputAmount),
            newlyRegistered,
            "input amount doesn't equal newly registered address"
        );
        assertEq(outputValueB, 0, "Non-zero outputValueB");
        assertFalse(isAsync, "Bridge is not synchronous");
    }
}
