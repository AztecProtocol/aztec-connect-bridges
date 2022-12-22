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
    address private constant REGISTER_ADDRESS = address(0xdeadbeef);

    address private rollupProcessor;

    ZoraAsk private ask;
    ZoraBridge private bridge;
    AddressRegistry private registry;
    ERC721PresetMinterPauserAutoId private nftContract;

    // Test AztecAssets.
    AztecTypes.AztecAsset private ethAsset =
        AztecTypes.AztecAsset({id: 0, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.ETH});
    AztecTypes.AztecAsset private erc20OutputAsset =
        AztecTypes.AztecAsset({id: 1, erc20Address: DAI, assetType: AztecTypes.AztecAssetType.ERC20});
    AztecTypes.AztecAsset private virtualAsset1 =
        AztecTypes.AztecAsset({id: 1, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL});
    AztecTypes.AztecAsset private virtualAsset84 =
        AztecTypes.AztecAsset({id: 84, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL});

    // @dev This method exists on RollupProcessor.sol. It's defined here in order to be able to receive ETH like a real
    //      rollup processor would.
    function receiveEthFromBridge(uint256 _interactionNonce) external payable {}

    function setUp() public {
        // In unit tests we set address of rollupProcessor to the address of this test contract
        rollupProcessor = address(this);

        // Initialize all contracts.
        registry = new AddressRegistry(rollupProcessor);
        ask = new ZoraAsk();
        bridge = new ZoraBridge(rollupProcessor, address(ask), address(registry));        

        // Get virtual assets.
        registry.convert(
            ethAsset,
            emptyAsset,
            virtualAsset1,
            emptyAsset,
            1, // _totalInputValue
            0, // _interactionNonce
            0, // _auxData
            address(0x0)
        );
        
        uint256 inputAmount = uint160(address(REGISTER_ADDRESS));
        // Register an address.
        registry.convert(
            virtualAsset1,
            emptyAsset,
            virtualAsset1,
            emptyAsset,
            inputAmount,
            0, // _interactionNonce
            0, // _auxData
            address(0x0)
        );
    }

    // Revert test cases -- fillAsk.
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

    function testCollectionAddressNotRegistered() public {
        // This auxData is out of range for the registry.
        uint64 auxData = uint64(registry.addressCount());
        vm.expectRevert(ErrorLib.InvalidAuxData.selector);
        bridge.convert(ethAsset, emptyAsset, virtualAsset1, emptyAsset, 0, 0, auxData, address(0));
    }

    // Revert test cases -- withdraw.
    function testInvalidVirtualTokenId() public {
        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        // No NFTs in the bridge.
        bridge.convert(virtualAsset1, emptyAsset, ethAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function testWithdrawAddressNotRegistered() public {
        // Successful fillAsk.
        bridge.convert(
            ethAsset, 
            emptyAsset, 
            virtualAsset1, 
            emptyAsset,
            0, 
            virtualAsset1.id,
            0, 
            address(0)
        );
        // This auxData is out of range for the registry.
        uint64 auxData = uint64(registry.addressCount());
        vm.expectRevert(ErrorLib.InvalidAuxData.selector);
        bridge.convert(virtualAsset1, emptyAsset, ethAsset, emptyAsset, 0, 0, auxData, address(0));
    }

    // Success test case -- fillAsk.
    function testSuccessfulAskFill() public {
        uint32 tokenId = 1559;
        uint32 collectionKey = 0;
        uint64 auxData = (uint64(tokenId) << 32) | uint64(collectionKey);
        uint256 inputValue = 2000;
        uint256 interactionNonce = 84;

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
            ethAsset, 
            emptyAsset, 
            virtualAsset1, 
            emptyAsset, 
            inputValue, 
            interactionNonce, 
            auxData, 
            address(0)
        );

        // Check outputs.
        assertEq(outputValueA, 1, "Output value A doesn't equal 1");
        assertEq(outputValueB, 0, "Output value B is not 0");
        assertTrue(!isAsync, "Bridge is incorrectly in an async mode");

        // Check that the internal nftAssets mapping is updated.
        (address storedCollection, uint256 storedTokenId) = bridge.nftAssets(interactionNonce);
        assertEq(storedCollection, REGISTER_ADDRESS, "Unexpected collection address");
        assertEq(storedTokenId, tokenId, "Unexpected tokenId");
    }

    // Success test case -- withdraw.
    function testSuccessfulWithdraw() public {
        uint32 tokenId = 0;
        uint32 collectionKey = 1;
        uint64 auxData = (uint64(tokenId) << 32) | uint64(collectionKey);
        uint256 inputValue = 2000;
        uint256 interactionNonce = 84;

        // Create test NFTS.
        nftContract = new ERC721PresetMinterPauserAutoId("test", "NFT", "");
        nftContract.mint(address(bridge));

        uint256 inputAmount = uint160(address(nftContract));
        // Register the NFT collection address. This will have index=1.
        registry.convert(
            virtualAsset1,
            emptyAsset,
            virtualAsset1,
            emptyAsset,
            inputAmount,
            0, // _interactionNonce
            0, // _auxData
            address(0x0)
        );
        
        // First fill an ask.
        bridge.convert(
            ethAsset, 
            emptyAsset, 
            virtualAsset1, 
            emptyAsset, 
            inputValue, 
            interactionNonce, 
            auxData, 
            address(0)
        );

        // Then withdraw. 
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
            virtualAsset84, 
            emptyAsset, 
            ethAsset, 
            emptyAsset, 
            0, // inputValue 
            0, // inputValue 
            0, // auxData
            address(0)
        );

        // Check outputs.
        assertEq(outputValueA, 0, "Output value A is not 0");
        assertEq(outputValueB, 0, "Output value B is not 0");
        assertTrue(!isAsync, "Bridge is incorrectly in an async mode");

        // Check that the internal nftAssets mapping is deleted.
        (address storedCollection, uint256 storedTokenId) = bridge.nftAssets(interactionNonce);
        assertEq(storedCollection, address(0), "Unexpected collection address");
        assertEq(storedTokenId, 0, "Unexpected tokenId");
    }
}
