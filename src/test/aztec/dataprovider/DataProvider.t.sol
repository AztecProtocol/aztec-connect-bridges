// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "../base/BridgeTestBase.sol";
import {DataProvider} from "../../../aztec/DataProvider.sol";

contract DataProviderTest is BridgeTestBase {
    DataProvider private provider;

    function setUp() public {
        provider = new DataProvider(address(ROLLUP_PROCESSOR));
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
        string[4] memory labels = ["Eth", "Dai", "vyDai", "vyEth"];

        for (uint256 i = 0; i < 4; i++) {
            provider.addAsset(i, labels[i]);
        }

        DataProvider.AssetData[] memory assets = provider.getAssets();

        for (uint256 i = 0; i < assets.length; i++) {
            DataProvider.AssetData memory asset = assets[i];
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
}
