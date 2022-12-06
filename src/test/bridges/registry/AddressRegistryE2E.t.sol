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
    AddressRegistry internal bridge;
    uint256 private id;
    AztecTypes.AztecAsset private ethAsset;
    AztecTypes.AztecAsset private virtualAsset1;
    uint256 public maxInt = type(uint160).max;

    event AddressRegistered(uint256 indexed addressCount, address indexed registeredAddress);

    function setUp() public {
        bridge = new AddressRegistry(address(ROLLUP_PROCESSOR));
        ethAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        virtualAsset1 =
            AztecTypes.AztecAsset({id: 0, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL});

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

    function testGetVirtualAssets() public {
        vm.warp(block.timestamp + 1 days);

        ROLLUP_ENCODER.defiInteractionL2(id, ethAsset, emptyAsset, virtualAsset1, emptyAsset, 0, 1);

        // Execute the rollup with the bridge interaction. Ensure that event as seen above is emitted.
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        // Check the output values are as expected
        assertEq(outputValueA, maxInt, "outputValueA doesn't equal maxInt");
        assertEq(outputValueB, 0, "Non-zero outputValueB");
        assertFalse(isAsync, "Bridge is not synchronous");
    }

    function testRegistration() public {
        uint160 inputAmount = uint160(0x2e782B05290A7fFfA137a81a2bad2446AD0DdFEA);
        
        vm.expectEmit(true, true, false, false);
        emit AddressRegistered(1, address(inputAmount));
        
        ROLLUP_ENCODER.defiInteractionL2(id, virtualAsset1, emptyAsset, virtualAsset1, emptyAsset, 0, inputAmount);

        // Execute the rollup with the bridge interaction. Ensure that event as seen above is emitted.
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        uint64 addressId = bridge.addressCount();
        uint64 registeredId = addressId;
        address newlyRegistered = bridge.addresses(registeredId);

        // Check the output values are as expected
        assertEq(address(inputAmount), newlyRegistered, "input amount doesn't equal newly registered address");
        assertEq(outputValueA, 0, "Non-zero outputValueA");
        assertEq(outputValueB, 0, "Non-zero outputValueB");
        assertFalse(isAsync, "Bridge is not synchronous");
    }
}
