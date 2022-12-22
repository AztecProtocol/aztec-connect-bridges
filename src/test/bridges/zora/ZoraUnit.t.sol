// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";

import {ERC721PresetMinterPauserAutoId} from "@openzeppelin/contracts/token/ERC721/presets/ERC721PresetMinterPauserAutoId.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {AddressRegistry} from "../../../bridges/registry/AddressRegistry.sol";
import {ZoraBridge} from "../../../bridges/zora/ZoraBridge.sol";
import {ZoraAsk} from "../../../bridges/zora/ZoraBridge.sol";

// @notice The purpose of this test is to directly test convert functionality of the bridge.
contract ZoraUnitTest is BridgeTestBase {
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant BENEFICIARY = address(11);

    address private rollupProcessor;

    ZoraAsk private ask;
    ZoraBridge private bridge;
    AddressRegistry private registry;

    ERC721PresetMinterPauserAutoId private nftContract;
    AztecTypes.AztecAsset private ethAsset =
        AztecTypes.AztecAsset({id: 0, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.ETH});
    AztecTypes.AztecAsset private erc20OutputAsset =
        AztecTypes.AztecAsset({id: 1, erc20Address: DAI, assetType: AztecTypes.AztecAssetType.ERC20});

    // @dev This method exists on RollupProcessor.sol. It's defined here in order to be able to receive ETH like a real
    //      rollup processor would.
    function receiveEthFromBridge(uint256 _interactionNonce) external payable {}

    function setUp() public {
        // In unit tests we set address of rollupProcessor to the address of this test contract
        rollupProcessor = address(this);
        registry = new AddressRegistry(rollupProcessor);
        ask = new ZoraAsk();
        bridge = new ZoraBridge(rollupProcessor, address(ask), address(registry));
    }

    function testInvalidCaller(address _callerAddress) public {
        vm.assume(_callerAddress != rollupProcessor);
        // Use HEVM cheatcode to call from a different address than is address(this)
        vm.prank(_callerAddress);
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function testInvalidInputAssetType() public {
        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function testInvalidOutputAssetType() public {
        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(ethAsset, emptyAsset, erc20OutputAsset, emptyAsset, 0, 0, 0, address(0));
    }
}
