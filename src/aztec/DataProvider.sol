// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRollupProcessor} from "./interfaces/IRollupProcessor.sol";

/**
 * @notice Helper used for mapping assets and bridges to more meaningful naming
 * @author Aztec Team
 */
contract DataProvider is Ownable {
    struct BridgeData {
        address bridgeAddress;
        uint256 bridgeAddressId;
        string label;
    }

    struct AssetData {
        address assetAddress;
        uint256 assetId;
        string label;
    }

    struct Bridges {
        mapping(uint256 => BridgeData) data;
        mapping(bytes32 => uint256) tagToId;
    }

    struct Assets {
        mapping(uint256 => AssetData) data;
        mapping(bytes32 => uint256) tagToId;
    }

    IRollupProcessor public immutable ROLLUP_PROCESSOR;
    Bridges internal bridges;
    Assets internal assets;

    constructor(address _rollupProcessor) {
        ROLLUP_PROCESSOR = IRollupProcessor(_rollupProcessor);
    }

    /**
     * @notice Adds a bridge with a specific tag
     * @dev Only callable by the owner
     * @param _bridgeAddressId The bridge address id for the bridge to list
     * @param _tag The tag to list with the bridge
     */
    function addBridge(uint256 _bridgeAddressId, string memory _tag) public onlyOwner {
        address bridgeAddress = ROLLUP_PROCESSOR.getSupportedBridge(_bridgeAddressId);
        if (bridgeAddress == address(0)) {
            revert("Invalid bridge");
        }
        bytes32 digest = keccak256(abi.encode(_tag));
        bridges.tagToId[digest] = _bridgeAddressId;
        bridges.data[_bridgeAddressId] = BridgeData({
            bridgeAddress: bridgeAddress,
            bridgeAddressId: _bridgeAddressId,
            label: _tag
        });
    }

    /**
     * @notice Adds an asset with a specific tag
     * @dev Only callable by the owner
     * @param _assetId The asset id of the asset to list
     * @param _tag The tag to list with the asset
     */
    function addAsset(uint256 _assetId, string memory _tag) public onlyOwner {
        address assetAddress = ROLLUP_PROCESSOR.getSupportedAsset(_assetId);
        bytes32 digest = keccak256(abi.encode(_tag));
        assets.tagToId[digest] = _assetId;
        assets.data[_assetId] = AssetData({assetAddress: assetAddress, assetId: _assetId, label: _tag});
    }

    /**
     * @notice Fetch the `BridgeData` related to a specific bridgeAddressId
     * @param _bridgeAddressId The bridge address id of the bridge to fetch
     * @return The BridgeData data structure for the given bridge
     */
    function getBridge(uint256 _bridgeAddressId) public view returns (BridgeData memory) {
        return bridges.data[_bridgeAddressId];
    }

    /**
     * @notice Fetch the `BridgeData` related to a specific tag
     * @param _tag The tag of the bridge to fetch
     * @return The BridgeData data structure for the given bridge
     */
    function getBridge(string memory _tag) public view returns (BridgeData memory) {
        return bridges.data[bridges.tagToId[keccak256(abi.encode(_tag))]];
    }

    /**
     * @notice Fetch the `AssetData` related to a specific assetId
     * @param _assetId The asset id of the asset to fetch
     * @return The AssetData data structure for the given asset
     */
    function getAsset(uint256 _assetId) public view returns (AssetData memory) {
        return assets.data[_assetId];
    }

    /**
     * @notice Fetch the `AssetData` related to a specific tag
     * @param _tag The tag of the asset to fetch
     * @return The AssetData data structure for the given asset
     */
    function getAsset(string memory _tag) public view returns (AssetData memory) {
        return assets.data[assets.tagToId[keccak256(abi.encode(_tag))]];
    }

    /**
     * @notice Fetch `AssetData` for all supported assets
     * @return A list of AssetData data structures, one for every asset
     */
    function getAssets() public view returns (AssetData[] memory) {
        uint256 assetCount = ROLLUP_PROCESSOR.getSupportedAssetsLength();
        AssetData[] memory assetDatas = new AssetData[](assetCount);
        for (uint256 i = 0; i < assetCount; i++) {
            assetDatas[i] = getAsset(i);
        }
        return assetDatas;
    }

    /**
     * @notice Fetch `BridgeData` for all supported bridges
     * @return A list of BridgeData data structures, one for every bridge
     */
    function getBridges() public view returns (BridgeData[] memory) {
        uint256 bridgeCount = ROLLUP_PROCESSOR.getSupportedBridgesLength();
        BridgeData[] memory bridgeDatas = new BridgeData[](bridgeCount);
        for (uint256 i = 1; i <= bridgeCount; i++) {
            bridgeDatas[i - 1] = getBridge(i);
        }
        return bridgeDatas;
    }
}
