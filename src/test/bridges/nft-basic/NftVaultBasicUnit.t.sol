// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";

// Example-specific imports
import {ERC721PresetMinterPauserAutoId} from
    "@openzeppelin/contracts/token/ERC721/presets/ERC721PresetMinterPauserAutoId.sol";
import {NftVault} from "../../../bridges/nft-basic/NftVault.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {AddressRegistry} from "../../../bridges/registry/AddressRegistry.sol";

// @notice The purpose of this test is to directly test convert functionality of the bridge.
contract NftVaultBasicUnitTest is BridgeTestBase {
    struct NftAsset {
        address collection;
        uint256 id;
    }

    address private rollupProcessor;
    // The reference to the example bridge
    NftVault private bridge;
    ERC721PresetMinterPauserAutoId private nftContract;
    uint256 private tokenIdToDeposit = 1;
    AddressRegistry private registry;
    address private constant registeredAddress = 0x2e782B05290A7fFfA137a81a2bad2446AD0DdFEA;
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    AztecTypes.AztecAsset private ethAsset =
        AztecTypes.AztecAsset({id: 0, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.ETH});
    AztecTypes.AztecAsset private virtualAsset1 =
        AztecTypes.AztecAsset({id: 1, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL});
    AztecTypes.AztecAsset private virtualAsset100 =
        AztecTypes.AztecAsset({id: 100, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL});
    AztecTypes.AztecAsset private erc20InputAsset =
        AztecTypes.AztecAsset({id: 1, erc20Address: DAI, assetType: AztecTypes.AztecAssetType.ERC20});

    event log(string, address);

    // @dev This method exists on RollupProcessor.sol. It's defined here in order to be able to receive ETH like a real
    //      rollup processor would.
    function receiveEthFromBridge(uint256 _interactionNonce) external payable {}

    function setUp() public {
        // In unit tests we set address of rollupProcessor to the address of this test contract
        rollupProcessor = address(this);
        // deploy address registry
        registry = new AddressRegistry(rollupProcessor);
        // Deploy a new nft vault bridge
        bridge = new NftVault(rollupProcessor, address(registry));
        // deploy new nft contract
        nftContract = new ERC721PresetMinterPauserAutoId("test", "NFT", "");
        nftContract.mint(address(this));
        nftContract.mint(address(this));
        nftContract.mint(address(this));

        nftContract.approve(address(bridge), 0);
        nftContract.approve(address(bridge), 1);
        nftContract.approve(address(bridge), 2);

        // get virtual assets
        registry.convert(
            ethAsset,
            emptyAsset,
            virtualAsset1,
            emptyAsset,
            1, // _totalInputValue - an amount of input asset A sent to the bridge
            0, // _interactionNonce
            0, // _auxData - not used
            address(0x0)
        );
        uint256 inputAmount = uint160(address(registeredAddress));
        // register an address
        registry.convert(
            virtualAsset1,
            emptyAsset,
            virtualAsset1,
            emptyAsset,
            inputAmount, // _totalInputValue - an amount of input asset A sent to the bridge
            0, // _interactionNonce
            0, // _auxData - not used in the example bridge
            address(0x0)
        );

        // Set ETH balance of bridge and BENEFICIARY to 0 for clarity (somebody sent ETH to that address on mainnet)
        vm.deal(address(bridge), 0);

        vm.label(address(bridge), "Basic NFT Vault Bridge");
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
        bridge.convert(ethAsset, emptyAsset, erc20InputAsset, emptyAsset, 0, 0, 0, address(0));
    }

    // @notice The purpose of this test is to directly test convert functionality of the bridge.
    function testGetVirtualAssetUnitTest() public {
        vm.warp(block.timestamp + 1 days);

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
            ethAsset, // _inputAssetA - definition of an input asset
            emptyAsset, // _inputAssetB - not used so can be left empty
            virtualAsset100, // _outputAssetA
            emptyAsset, // _outputAssetB - not used so can be left empty
            1, // _totalInputValue - an amount of input asset A sent to the bridge
            0, // _interactionNonce
            0, // _auxData
            address(0) // _rollupBeneficiary - address, the subsidy will be sent to
        );

        assertEq(outputValueA, 1, "Output value A doesn't equal 1");
        assertEq(outputValueB, 0, "Output value B is not 0");
        assertTrue(!isAsync, "Bridge is incorrectly in an async mode");
    }

    function testGetVirtualAssetShouldFail() public {
        vm.warp(block.timestamp + 1 days);

        vm.expectRevert();
        // should fail because sending more than 1 wei
        bridge.convert(
            ethAsset, // _inputAssetA - definition of an input asset
            emptyAsset, // _inputAssetB - not used so can be left empty
            virtualAsset100, // _outputAssetA
            emptyAsset, // _outputAssetB - not used so can be left empty
            2, // _totalInputValue - an amount of input asset A sent to the bridge
            0, // _interactionNonce
            0, // _auxData - not used in this call
            address(0) // _rollupBeneficiary - address, the subsidy will be sent to
        );
    }

    function testDeposit() public {
        vm.warp(block.timestamp + 1 days);

        address collection = address(nftContract);
        address from = address(this);
        bridge.matchDeposit(virtualAsset100.id, collection, from, tokenIdToDeposit);
        (address returnedCollection, uint256 returnedId) = bridge.tokens(virtualAsset100.id);
        assertEq(returnedId, tokenIdToDeposit, "nft token id does not match input");
        assertEq(returnedCollection, collection, "collection data does not match");
    }

    function testDepositFailWithDuplicateNft() public {
        testDeposit();
        vm.warp(block.timestamp + 1 days);

        address collection = address(nftContract);
        address from = address(this);

        vm.expectRevert();
        // should fail because an NFT with this id has already been deposited
        bridge.matchDeposit(virtualAsset100.id, collection, from, tokenIdToDeposit);
    }

    function testWithdraw() public {
        testDeposit();
        uint64 auxData = registry.id() - 1;
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
            virtualAsset100, // _inputAssetA - definition of an input asset
            emptyAsset, // _inputAssetB - not used so can be left empty
            ethAsset, // _outputAssetA
            emptyAsset, // _outputAssetB - not used so can be left empty
            1, // _totalInputValue - an amount of input asset A sent to the bridge
            0, // _interactionNonce
            auxData, // _auxData - the id of the eth address to withdraw to from the registry
            address(0)
        );
        address owner = nftContract.ownerOf(tokenIdToDeposit);
        assertEq(registeredAddress, owner, "registered address is not the owner");
        assertEq(outputValueA, 0, "Output value A is not 0");
        assertEq(outputValueB, 0, "Output value B is not 0");
        assertTrue(!isAsync, "Bridge is incorrectly in an async mode");

        (address _a, uint256 _id) = bridge.tokens(virtualAsset100.id);
        assertEq(_a, address(0), "collection address is not 0");
        assertEq(_id, 0, "token id is not 0");
    }

    function testWithdrawUnregisteredNft() public {
        testDeposit();
        uint64 auxData = registry.id() - 1;
        vm.expectRevert();
        // should fail because no NFT has been registered with this virtual asset
        bridge.convert(
            virtualAsset1, // _inputAssetA - definition of an input asset
            emptyAsset, // _inputAssetB - not used so can be left empty
            ethAsset, // _outputAssetA
            emptyAsset, // _outputAssetB - not used so can be left empty
            1, // _totalInputValue - an amount of input asset A sent to the bridge
            0, // _interactionNonce
            auxData,
            address(0)
        );
    }

    function testWithdrawUnregisteredWithdrawAddress() public {
        testDeposit();
        uint64 auxData = 1000;
        vm.expectRevert();
        // should fail because no withdraw address has been registered with this id
        bridge.convert(
            virtualAsset1, // _inputAssetA - definition of an input asset
            emptyAsset, // _inputAssetB - not used so can be left empty
            ethAsset, // _outputAssetA
            emptyAsset, // _outputAssetB - not used so can be left empty
            1, // _totalInputValue - an amount of input asset A sent to the bridge
            0, // _interactionNonce
            auxData,
            address(0)
        );
    }
}
