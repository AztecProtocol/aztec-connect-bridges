// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../../lib/rollup-encoder/src/libraries/AztecTypes.sol";

// Example-specific imports
import {AddressRegistry} from "../../../bridges/registry/AddressRegistry.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

// @notice The purpose of this test is to directly test convert functionality of the bridge.
contract AddressRegistryUnitTest is BridgeTestBase {
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private rollupProcessor;
    AddressRegistry private bridge;
    uint256 public maxInt =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    // @dev This method exists on RollupProcessor.sol. It's defined here in order to be able to receive ETH like a real
    //      rollup processor would.
    function receiveEthFromBridge(uint256 _interactionNonce) external payable {}

    function setUp() public {
        // In unit tests we set address of rollupProcessor to the address of this test contract
        rollupProcessor = address(this);

        // Deploy a new example bridge
        bridge = new AddressRegistry(rollupProcessor);

        // Set ETH balance of bridge and BENEFICIARY to 0 for clarity (somebody sent ETH to that address on mainnet)
        // vm.deal(address(bridge), 0);

        // Use the label cheatcode to mark the address with "AddressRegistry Bridge" in the traces
        vm.label(address(bridge), "AddressRegistry Bridge");
    }

    function testInvalidCaller(address _callerAddress) public {
        vm.assume(_callerAddress != rollupProcessor);
        // Use HEVM cheatcode to call from a different address than is address(this)
        vm.prank(_callerAddress);
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(
            emptyAsset,
            emptyAsset,
            emptyAsset,
            emptyAsset,
            0,
            0,
            0,
            address(0)
        );
    }

    function testInvalidInputAssetType() public {
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: DAI,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(
            inputAsset,
            emptyAsset,
            emptyAsset,
            emptyAsset,
            0,
            0,
            0,
            address(0)
        );
    }

    function testInvalidOutputAssetType() public {
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: DAI,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(
            emptyAsset,
            emptyAsset,
            outputAsset,
            emptyAsset,
            0,
            0,
            0,
            address(0)
        );
    }

    // @notice The purpose of this test is to directly test convert functionality of the bridge.
    function testGetBackMaxVirtualAssets() public {
        vm.warp(block.timestamp + 1 days);

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 0,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.VIRTUAL
        });

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge
            .convert(
                emptyAsset,
                emptyAsset,
                outputAssetA,
                emptyAsset,
                0, // _totalInputValue - an amount of input asset A sent to the bridge
                0, // _interactionNonce
                0, // _auxData - not used in the example bridge
                address(0x0)
            );

        assertEq(outputValueA, maxInt, "Output value A doesn't equal maxInt");
        assertEq(outputValueB, 0, "Output value B is not 0");
        assertTrue(!isAsync, "Bridge is incorrectly in an async mode");
    }

    function testRegistringAnAddress() public {
        vm.warp(block.timestamp + 1 days);

        // Define input and output assets
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 0,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.VIRTUAL
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 0,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.VIRTUAL
        });

        uint160 inputAmount = uint160(0x2e782B05290A7fFfA137a81a2bad2446AD0DdFEA);

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge
            .convert(
                inputAssetA,
                emptyAsset,
                outputAssetA,
                emptyAsset,
                inputAmount, // _totalInputValue - an amount of input asset A sent to the bridge
                0, // _interactionNonce
                0, // _auxData - not used in the example bridge
                address(0x0)
            );

        address newlyRegistered = bridge.addresses(0);

        assertEq(
            address(inputAmount),
            newlyRegistered,
            "Address not registered"
        );
        assertEq(outputValueA, 0, "Output value is not 0");
        assertEq(outputValueB, 0, "Output value B is not 0");
        assertTrue(!isAsync, "Bridge is incorrectly in an async mode");
    }
}
