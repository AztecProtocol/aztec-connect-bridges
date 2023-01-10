// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {BridgeTestBase} from "../base/BridgeTestBase.sol";
import {DataProvider} from "../../../aztec/DataProvider.sol";

contract DataProviderTest is BridgeTestBase {
    DataProvider private provider;

    function setUp() public {
        provider = new DataProvider(address(ROLLUP_PROCESSOR));

        // fund yearn bridge to ensure that there are funds.
        SUBSIDY.topUp{value: 10 ether}(ROLLUP_PROCESSOR.getSupportedBridge(7), 0);
        SUBSIDY.topUp{value: 10 ether}(ROLLUP_PROCESSOR.getSupportedBridge(7), 1);
    }

    function testAddMultipleAssetsAndBridgesWrongInput() public {
        uint256[] memory assetIds = new uint256[](4);
        uint256[] memory bridgeAddressIds = new uint256[](5);
        string[] memory assetTags = new string[](4);
        string[] memory bridgeTags = new string[](4);

        vm.expectRevert("Invalid input lengths");
        provider.addAssetsAndBridges(assetIds, assetTags, bridgeAddressIds, bridgeTags);

        bridgeAddressIds = new uint256[](4);
        assetTags = new string[](5);

        vm.expectRevert("Invalid input lengths");
        provider.addAssetsAndBridges(assetIds, assetTags, bridgeAddressIds, bridgeTags);
    }

    function testAddMultipleAssetsAndBridges() public {
        uint256[] memory assetIds = new uint256[](4);
        uint256[] memory bridgeAddressIds = new uint256[](4);
        string[] memory assetTags = new string[](4);
        string[] memory bridgeTags = new string[](4);

        for (uint256 i = 0; i < 4; i++) {
            assetIds[i] = i;
            bridgeAddressIds[i] = i + 1;
            assetTags[i] = string(abi.encodePacked("asset", i));
            bridgeTags[i] = string(abi.encodePacked("bridge", i + 1));
        }

        vm.prank(address(1));
        vm.expectRevert("Ownable: caller is not the owner");
        provider.addAssetsAndBridges(assetIds, assetTags, bridgeAddressIds, bridgeTags);

        provider.addAssetsAndBridges(assetIds, assetTags, bridgeAddressIds, bridgeTags);

        DataProvider.AssetData[] memory assets = provider.getAssets();
        assertEq(assets.length, ROLLUP_PROCESSOR.getSupportedAssetsLength() + 1);
        for (uint256 i = 0; i < assets.length; i++) {
            DataProvider.AssetData memory asset = assets[i];
            if (i < assetIds.length) {
                assertEq(asset.assetAddress, ROLLUP_PROCESSOR.getSupportedAsset(asset.assetId));
                assertEq(asset.label, assetTags[i]);
                assertEq(asset.assetId, i);
            } else {
                assertEq(asset.assetAddress, address(0));
                assertEq(asset.label, "");
                assertEq(asset.assetId, 0);
            }
        }

        DataProvider.BridgeData[] memory bridges = provider.getBridges();
        for (uint256 i = 0; i < bridgeTags.length; i++) {
            DataProvider.BridgeData memory bridge = bridges[i];
            assertEq(bridge.bridgeAddressId, i + 1, "bridge address id invalid");
            assertEq(
                bridge.bridgeAddress,
                ROLLUP_PROCESSOR.getSupportedBridge(bridge.bridgeAddressId),
                "bridge address invalid"
            );
            assertEq(bridge.label, bridgeTags[i], "bridge label invalid");
        }
    }

    function testGetAssetsEmptyLabels() public {
        DataProvider.AssetData[] memory assets = provider.getAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            DataProvider.AssetData memory asset = assets[i];
            assertEq(asset.assetAddress, address(0));
            assertEq(asset.assetId, 0);
            assertEq(asset.label, "");
        }
    }

    function testGetAssetsWithLabels() public {
        string[4] memory labels = ["eth", "dai", "vydai", "vyeth"];

        for (uint256 i = 0; i < 4; i++) {
            provider.addAsset(i, labels[i]);
        }

        DataProvider.AssetData[] memory assets = provider.getAssets();
        assertEq(assets.length, ROLLUP_PROCESSOR.getSupportedAssetsLength() + 1); // remember Eth base asset

        for (uint256 i = 0; i < assets.length; i++) {
            DataProvider.AssetData memory asset = assets[i];
            if (i < labels.length) {
                assertEq(asset.assetAddress, ROLLUP_PROCESSOR.getSupportedAsset(i));
                assertEq(asset.label, labels[i]);
                assertEq(asset.assetId, i);
            } else {
                assertEq(asset.assetAddress, address(0));
                assertEq(asset.label, "");
                assertEq(asset.assetId, 0);
            }
        }
    }

    function testGetAssetWithLabels() public {
        string[4] memory labels = ["Eth", "Dai", "vyDai", "vyEth"];

        for (uint256 i = 0; i < 4; i++) {
            provider.addAsset(i, labels[i]);
            DataProvider.AssetData memory asset = provider.getAsset(labels[i]);
            assertEq(asset.assetAddress, ROLLUP_PROCESSOR.getSupportedAsset(i));
            assertEq(asset.label, labels[i]);
            assertEq(asset.assetId, i);
        }
    }

    function testGetBridgesEmptyLabels() public {
        DataProvider.BridgeData[] memory bridges = provider.getBridges();

        for (uint256 i = 0; i < bridges.length; i++) {
            DataProvider.BridgeData memory bridge = bridges[i];
            assertEq(bridge.bridgeAddress, address(0));
            assertEq(bridge.bridgeAddressId, 0);
            assertEq(bridge.label, "");
        }
    }

    function testGetBridgesWithLabels() public {
        uint256 bridgeCount = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        string[] memory labels = new string[](bridgeCount + 1);
        labels[0] = "start";

        for (uint256 i = 1; i <= bridgeCount; i++) {
            // Not a proper string but useful to distinguish between them
            labels[i] = string(abi.encodePacked("Bridge", bytes4(keccak256(abi.encode(i)))));
            provider.addBridge(i, labels[i]);
        }

        DataProvider.BridgeData[] memory bridges = provider.getBridges();

        // Offset by one because of we are storing bridges
        for (uint256 i = 0; i < bridges.length; i++) {
            DataProvider.BridgeData memory bridge = bridges[i];
            assertEq(bridge.bridgeAddress, ROLLUP_PROCESSOR.getSupportedBridge(i + 1));
            assertEq(bridge.bridgeAddressId, i + 1);
            assertEq(bridge.label, labels[i + 1]);
        }
    }

    function testGetBridgeWithLabels() public {
        uint256 bridgeCount = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        string[] memory labels = new string[](bridgeCount + 1);
        labels[0] = "start";

        for (uint256 i = 1; i <= bridgeCount; i++) {
            // Not a proper string but useful to distinguish between them
            labels[i] = string(abi.encodePacked("Bridge", bytes4(keccak256(abi.encode(i)))));
            provider.addBridge(i, labels[i]);

            DataProvider.BridgeData memory bridge = provider.getBridge(labels[i]);
            assertEq(bridge.bridgeAddress, ROLLUP_PROCESSOR.getSupportedBridge(i));
            assertEq(bridge.bridgeAddressId, i);
            assertEq(bridge.label, labels[i]);
        }
    }

    function testHappySubsidyHelper() public {
        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory eth = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory vyvault =
            ROLLUP_ENCODER.getRealAztecAsset(0xa258C4606Ca8206D8aA700cE2143D7db854D168c);

        vm.warp(block.timestamp + 1 days);

        uint256 bridgeCallData = ROLLUP_ENCODER.encodeBridgeCallData(7, eth, empty, vyvault, empty, 0);
        (uint256 criteria, uint256 subsidy, uint256 gasUnits) = provider.getAccumulatedSubsidyAmount(bridgeCallData);
        assertEq(criteria, 0, "Subsidy have accrued");
        assertGt(subsidy, 0, "No subsidy accrued");
        assertGe(subsidy, gasUnits * block.basefee, "Invalid gas units accrued");
        assertEq(gasUnits, subsidy / block.basefee, "Invalid gas units accrued");

        {
            uint256 bridgeCallData = ROLLUP_ENCODER.encodeBridgeCallData(7, vyvault, empty, eth, empty, 1);
            (uint256 criteria, uint256 subsidy, uint256 gasUnits) = provider.getAccumulatedSubsidyAmount(bridgeCallData);
            assertEq(criteria, 1, "Wrong criteria");
            assertGe(subsidy, 0, "Subsidy accrued");
            assertGe(subsidy, gasUnits * block.basefee, "Invalid gas units accrued");
            assertEq(gasUnits, subsidy / block.basefee, "Invalid gas units accrued");
        }
    }

    function testHappySubsidyHelper2InOut() public {
        AztecTypes.AztecAsset memory eth = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory dai = ROLLUP_ENCODER.getRealAztecAsset(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        uint256 bridgeCallData = ROLLUP_ENCODER.encodeBridgeCallData(7, dai, eth, dai, eth, 0);
        (uint256 criteria, uint256 subsidy, uint256 gasUnits) = provider.getAccumulatedSubsidyAmount(bridgeCallData);
        assertEq(criteria, 0, "Wrong criteria");
        assertGt(subsidy, 0, "No subsidy accrued");
        assertGe(subsidy, gasUnits * block.basefee, "Invalid gas units accrued");
        assertEq(gasUnits, subsidy / block.basefee, "Invalid gas units accrued");
    }

    function testHappySubsidyHelperVirtual() public {
        AztecTypes.AztecAsset memory eth = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory virtualAsset =
            AztecTypes.AztecAsset({id: 0, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL});

        uint256 bridgeCallData = ROLLUP_ENCODER.encodeBridgeCallData(7, virtualAsset, eth, virtualAsset, eth, 0);
        (uint256 criteria, uint256 subsidy, uint256 gasUnits) = provider.getAccumulatedSubsidyAmount(bridgeCallData);
        assertEq(criteria, 0, "Wrong criteria");
        assertGt(subsidy, 0, "No subsidy accrued");
        assertGe(subsidy, gasUnits * block.basefee, "Invalid gas units accrued");
        assertEq(gasUnits, subsidy / block.basefee, "Invalid gas units accrued");
    }

    function testUnHappySubsidyHelper() public {
        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory dai = ROLLUP_ENCODER.getRealAztecAsset(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        uint256 bridgeCallData = ROLLUP_ENCODER.encodeBridgeCallData(1, dai, empty, dai, empty, 0);
        (uint256 criteria, uint256 subsidy, uint256 gasUnits) = provider.getAccumulatedSubsidyAmount(bridgeCallData);
        assertEq(criteria, 0, "Wrong criteria");
        assertEq(subsidy, 0, "Subsidy have accrued");
        assertGe(subsidy, gasUnits * block.basefee, "Invalid gas units accrued");
        assertEq(gasUnits, subsidy / block.basefee, "Invalid gas units accrued");
    }

    function testZeroBaseFee() public {
        AztecTypes.AztecAsset memory eth = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory virtualAsset =
            AztecTypes.AztecAsset({id: 0, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL});

        uint256 bridgeCallData = ROLLUP_ENCODER.encodeBridgeCallData(7, virtualAsset, eth, virtualAsset, eth, 0);

        vm.fee(0);

        (uint256 criteria, uint256 subsidy, uint256 gasUnits) = provider.getAccumulatedSubsidyAmount(bridgeCallData);
        assertEq(criteria, 0, "Wrong criteria");
        assertEq(subsidy, 0, "No subsidy accrued");
        assertEq(subsidy, 0, "Invalid gas units accrued");
        assertEq(gasUnits, 0, "Invalid gas units accrued");
    }
}
