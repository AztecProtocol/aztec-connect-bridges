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

    uint256 public maxInt =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    function setUp() public {
        // Deploy a new example bridge
        bridge = new AddressRegistry(address(ROLLUP_PROCESSOR));

        // Use the label cheatcode to mark the address with "Example Bridge" in the traces
        vm.label(address(bridge), "Address Registry Bridge");

        // Impersonate the multi-sig to add a new bridge
        vm.startPrank(MULTI_SIG);

        // List the example-bridge with a gasLimit of 120k
        // WARNING: If you set this value too low the interaction will fail for seemingly no reason!
        // OTOH if you se it too high bridge users will pay too much
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 120000);

        vm.stopPrank();

        // Fetch the id of the example bridge
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();
    }

    // @dev In order to avoid overflows we set _depositAmount to be uint96 instead of uint256.
    function testAddressRegistryE2ETest(uint96 _depositAmount) public {
        vm.assume(_depositAmount > 1);
        vm.warp(block.timestamp + 1 days);

        // Define input and output assets
        AztecTypes.AztecAsset memory virtualAsset1 = AztecTypes.AztecAsset({
            id: 0,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.VIRTUAL
        });

        // Computes the encoded data for the specific bridge interaction
        ROLLUP_ENCODER.defiInteractionL2(
            id,
            emptyAsset,
            emptyAsset,
            virtualAsset1,
            emptyAsset,
            0,
            0
        );

        // Execute the rollup with the bridge interaction. Ensure that event as seen above is emitted.
        (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        ) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        // Check the output values are as expected
        assertEq(
            outputValueA,
            maxInt,
            "outputValueA doesn't equal maxInt"
        );
        assertEq(outputValueB, 0, "Non-zero outputValueB");
        assertFalse(isAsync, "Bridge is not synchronous");

        uint160 inputAmount = uint160(0x2e782B05290A7fFfA137a81a2bad2446AD0DdFEA);

        ROLLUP_ENCODER.defiInteractionL2(
            id,
            virtualAsset1,
            emptyAsset,
            emptyAsset,
            emptyAsset,
            0,
            inputAmount
        );

        // Execute the rollup with the bridge interaction. Ensure that event as seen above is emitted.
        (outputValueA, outputValueB, isAsync) = ROLLUP_ENCODER
            .processRollupAndGetBridgeResult();

        uint64 addressId = bridge.id();
        uint64 registeredId = addressId--;
        address newlyRegistered = bridge.addresses(registeredId);

        // Check the output values are as expected
        assertEq(
            inputAmount,
            newlyRegistered,
            "input amount doesn't equal newly registered address"
        );
        assertEq(outputValueB, 0, "Non-zero outputValueB");
        assertFalse(isAsync, "Bridge is not synchronous");
    }
}
