// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {AztecTypes} from "./../../../aztec/libraries/AztecTypes.sol";
import {BridgeTestBase} from "./BridgeTestBase.sol";

contract EncodeBridgeCallDataTest is BridgeTestBase {
    uint256 private constant VIRTUAL_ASSET_ID_FLAG_SHIFT = 29;
    uint256 private constant VIRTUAL_ASSET_ID_FLAG = 0x20000000; // 2 ** 29

    function testVirtualAssetFlagApplied(uint32 _assetId) public {
        uint256 assetId = bound(_assetId, 0, VIRTUAL_ASSET_ID_FLAG - 1);
        uint256 virtualAsset = assetId + VIRTUAL_ASSET_ID_FLAG;

        AztecTypes.AztecAsset memory decoded = _decodeAsset(virtualAsset);
        assertEq(decoded.erc20Address, address(0), "Virtual asset has erc20 address");
        assertEq(decoded.id, assetId, "Asset Id not matching");
        assertTrue(decoded.assetType == AztecTypes.AztecAssetType.VIRTUAL, "Not virtual");
    }

    function testNonVirtual(uint32 _assetId) public {
        uint256 assetId = bound(_assetId, 0, ROLLUP_PROCESSOR.getSupportedAssetsLength());

        address assetAddress = ROLLUP_PROCESSOR.getSupportedAsset(assetId);

        AztecTypes.AztecAsset memory decoded = _decodeAsset(assetId);

        assertEq(decoded.erc20Address, assetAddress, "asset address not matching");
        assertEq(decoded.id, assetId, "Asset Id not matching");
        if (assetAddress == address(0)) {
            assertTrue(decoded.assetType == AztecTypes.AztecAssetType.ETH, "Not eth");
        } else {
            assertTrue(decoded.assetType == AztecTypes.AztecAssetType.ERC20, "Not erc20");
        }
    }

    function _decodeAsset(uint256 _assetId) internal view returns (AztecTypes.AztecAsset memory) {
        if (_assetId >> VIRTUAL_ASSET_ID_FLAG_SHIFT == 1) {
            return
                AztecTypes.AztecAsset({
                    id: _assetId - VIRTUAL_ASSET_ID_FLAG,
                    erc20Address: address(0),
                    assetType: AztecTypes.AztecAssetType.VIRTUAL
                });
        } else {
            address erc20Address = ROLLUP_PROCESSOR.getSupportedAsset(_assetId);
            return
                AztecTypes.AztecAsset({
                    id: _assetId,
                    erc20Address: erc20Address,
                    assetType: erc20Address == address(0)
                        ? AztecTypes.AztecAssetType.ETH
                        : AztecTypes.AztecAssetType.ERC20
                });
        }
    }
}
