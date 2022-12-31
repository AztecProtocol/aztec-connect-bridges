// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";

// Example-specific imports
import {NftVault} from "../../../bridges/nft-basic/NftVault.sol";
import {AddressRegistry} from "../../../bridges/registry/AddressRegistry.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {ERC721PresetMinterPauserAutoId} from
    "@openzeppelin/contracts/token/ERC721/presets/ERC721PresetMinterPauserAutoId.sol";

/**
 * @notice The purpose of this test is to test the bridge in an environment that is as close to the final deployment
 *         as possible without spinning up all the rollup infrastructure (sequencer, proof generator etc.).
 */
contract NftVaultBasicE2ETest is BridgeTestBase {
    NftVault internal bridge;
    NftVault internal bridge2;
    AddressRegistry private registry;
    ERC721PresetMinterPauserAutoId private nftContract;

    // To store the id of the bridge after being added
    uint256 private bridgeId;
    uint256 private bridge2Id;
    uint256 private registryBridgeId;
    uint256 private tokenIdToDeposit = 1;
    address private constant REGISTER_ADDRESS = 0x2e782B05290A7fFfA137a81a2bad2446AD0DdFEA;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    AztecTypes.AztecAsset private ethAsset;
    AztecTypes.AztecAsset private virtualAsset1 =
        AztecTypes.AztecAsset({id: 1, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL});
    AztecTypes.AztecAsset private virtualAsset100 =
        AztecTypes.AztecAsset({id: 100, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL});
    AztecTypes.AztecAsset private erc20InputAsset =
        AztecTypes.AztecAsset({id: 1, erc20Address: DAI, assetType: AztecTypes.AztecAssetType.ERC20});

    event NftDeposit(uint256 indexed virtualAssetId, address indexed collection, uint256 indexed tokenId);
    event NftWithdraw(uint256 indexed virtualAssetId, address indexed collection, uint256 indexed tokenId);

    function setUp() public {
        registry = new AddressRegistry(address(ROLLUP_PROCESSOR));
        bridge = new NftVault(address(ROLLUP_PROCESSOR), address(registry));
        bridge2 = new NftVault(address(ROLLUP_PROCESSOR), address(registry));
        nftContract = new ERC721PresetMinterPauserAutoId("test", "NFT", "");
        nftContract.mint(address(this));
        nftContract.mint(address(this));
        nftContract.mint(address(this));

        nftContract.approve(address(bridge), 0);
        nftContract.approve(address(bridge), 1);
        nftContract.approve(address(bridge), 2);

        ethAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));

        vm.label(address(registry), "AddressRegistry Bridge");
        vm.label(address(bridge), "NftVault Bridge");

        // Impersonate the multi-sig to add a new bridge
        vm.startPrank(MULTI_SIG);

        // WARNING: If you set this value too low the interaction will fail for seemingly no reason!
        // OTOH if you se it too high bridge users will pay too much
        ROLLUP_PROCESSOR.setSupportedBridge(address(registry), 120000);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 120000);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge2), 120000);

        vm.stopPrank();

        // Fetch the id of the bridges
        registryBridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength() - 2;
        bridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength() - 1;
        bridge2Id = ROLLUP_PROCESSOR.getSupportedBridgesLength();
        // get virutal assets to register an address
        ROLLUP_ENCODER.defiInteractionL2(registryBridgeId, ethAsset, emptyAsset, virtualAsset1, emptyAsset, 0, 1);
        ROLLUP_ENCODER.processRollupAndGetBridgeResult();
        // get virutal assets to register 2nd NftVault
        ROLLUP_ENCODER.defiInteractionL2(registryBridgeId, ethAsset, emptyAsset, virtualAsset1, emptyAsset, 0, 1);
        ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        // register an address
        uint160 inputAmount = uint160(REGISTER_ADDRESS);
        ROLLUP_ENCODER.defiInteractionL2(
            registryBridgeId, virtualAsset1, emptyAsset, virtualAsset1, emptyAsset, 0, inputAmount
        );
        ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        // register 2nd NftVault in AddressRegistry
        uint160 bridge2AddressAmount = uint160(address(bridge2));
        ROLLUP_ENCODER.defiInteractionL2(
            registryBridgeId, virtualAsset1, emptyAsset, virtualAsset1, emptyAsset, 0, bridge2AddressAmount
        );
    }

    function testDeposit() public {
        // get virtual asset before deposit
        ROLLUP_ENCODER.defiInteractionL2(bridgeId, ethAsset, emptyAsset, virtualAsset100, emptyAsset, 0, 1);

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        assertEq(outputValueA, 1, "Output value A doesn't equal 1");
        assertEq(outputValueB, 0, "Output value B is not 0");
        assertTrue(!isAsync, "Bridge is incorrectly in an async mode");

        address collection = address(nftContract);

        vm.expectEmit(true, true, false, false);
        emit NftDeposit(virtualAsset100.id, collection, tokenIdToDeposit);
        bridge.transferFromAndMatch(virtualAsset100.id, collection, tokenIdToDeposit);
        (address returnedCollection, uint256 returnedId) = bridge.nftAssets(virtualAsset100.id);
        assertEq(returnedId, tokenIdToDeposit, "nft token id does not match input");
        assertEq(returnedCollection, collection, "collection data does not match");
    }

    function testWithdraw() public {
        testDeposit();
        uint64 auxData = uint64(registry.addressCount() - 2);

        vm.expectEmit(true, true, false, false);
        emit NftWithdraw(virtualAsset100.id, address(nftContract), tokenIdToDeposit);
        ROLLUP_ENCODER.defiInteractionL2(bridgeId, virtualAsset100, emptyAsset, ethAsset, emptyAsset, auxData, 1);

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();
        address owner = nftContract.ownerOf(tokenIdToDeposit);
        assertEq(REGISTER_ADDRESS, owner, "registered address is not the owner");
        assertEq(outputValueA, 0, "Output value A is not 0");
        assertEq(outputValueB, 0, "Output value B is not 0");
        assertTrue(!isAsync, "Bridge is incorrectly in an async mode");

        (address _a, uint256 _id) = bridge.nftAssets(virtualAsset100.id);
        assertEq(_a, address(0), "collection address is not 0");
        assertEq(_id, 0, "token id is not 0");
    }

    function testTransfer() public {
        testDeposit();
        (address collection, uint256 tokenId) = bridge.nftAssets(virtualAsset100.id);
        uint64 auxData = uint64(registry.addressCount() - 1);

        vm.expectEmit(true, true, false, false);
        // ran test and determined the interaction nonce of the tx will be 128
        emit NftDeposit(128, collection, tokenId);
        ROLLUP_ENCODER.defiInteractionL2(bridgeId, virtualAsset100, emptyAsset, virtualAsset1, emptyAsset, auxData, 1);

        ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        // check that the nft was transferred to the second NftVault
        (address returnedCollection, uint256 returnedId) = bridge2.nftAssets(128);
        assertEq(returnedId, tokenIdToDeposit, "nft token id does not match input");
        assertEq(returnedCollection, collection, "collection data does not match");
    }
}
