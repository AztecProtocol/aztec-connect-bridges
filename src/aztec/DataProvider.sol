// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IRollupProcessor} from "./interfaces/IRollupProcessor.sol";

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

    function addAsset(uint256 _assetId, string memory _tag) public onlyOwner {
        address assetAddress = ROLLUP_PROCESSOR.getSupportedAsset(_assetId);
        if (assetAddress == address(0)) {
            revert("Invalid asset");
        }
        bytes32 digest = keccak256(abi.encode(_tag));
        assets.tagToId[digest] = _assetId;
        assets.data[_assetId] = AssetData({assetAddress: assetAddress, assetId: _assetId, label: _tag});
    }

    function getBridge(uint256 _bridgeAddressId) public view returns (BridgeData memory) {
        return bridges.data[_bridgeAddressId];
    }

    function getBridge(string memory _tag) public view returns (BridgeData memory) {
        return bridges.data[bridges.tagToId[keccak256(abi.encode(_tag))]];
    }

    function getAsset(uint256 _assetId) public view returns (AssetData memory) {
        return assets.data[_assetId];
    }

    function getAsset(string memory _tag) public view returns (AssetData memory) {
        return assets.data[assets.tagToId[keccak256(abi.encode(_tag))]];
    }
}
