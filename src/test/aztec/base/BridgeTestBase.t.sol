// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {AztecTypes} from "./../../../aztec/libraries/AztecTypes.sol";
import {BridgeTestBase} from "./BridgeTestBase.sol";

contract BridgeTestBaseTest is BridgeTestBase {
    uint256 private constant VIRTUAL_ASSET_ID_FLAG_SHIFT = 29;
    uint256 private constant VIRTUAL_ASSET_ID_FLAG = 0x20000000; // 2 ** 29
    uint256 internal constant ADDRESS_MASK = 0x00ffffffffffffffffffffffffffffffffffffffff;

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

    function testGetDefiBridgeProcessedData() public {
        uint256 outputValueAReference = 896;
        uint256 outputValueBReference = 351;

        vm.recordLogs();
        emit DefiBridgeProcessed(126, 12, 41, outputValueAReference, outputValueBReference, true, "");
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _getDefiBridgeProcessedData();

        assertEq(outputValueA, outputValueAReference, "Incorrect outputValueA");
        assertEq(outputValueB, outputValueBReference, "Incorrect outputValueB");
        assertFalse(isAsync, "Interaction unexpectedly async");
    }

    function testGetDefiBridgeProcessedDataAsync() public {
        vm.recordLogs();
        emit AsyncDefiBridgeProcessed(126, 12, 1e18);
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = _getDefiBridgeProcessedData();

        assertEq(outputValueA, 0, "Incorrect outputValueA");
        assertEq(outputValueB, 0, "Incorrect outputValueB");
        assertTrue(isAsync, "Interaction unexpectedly async");
    }

    function testGetDefiBridgeProcessedDataIncorrectNumEvents() public {
        vm.recordLogs();
        emit DefiBridgeProcessed(126, 12, 41, 9769836, 35345, true, "");
        emit DefiBridgeProcessed(12354, 354, 623, 26634, 6342, true, "");
        vm.expectRevert("Incorrect number of events found");
        _getDefiBridgeProcessedData();
    }

    function testGetDefiBridgeProcessedDataIncorrectNumEventsAsync() public {
        vm.recordLogs();
        emit AsyncDefiBridgeProcessed(126, 12, 1e18);
        emit AsyncDefiBridgeProcessed(126, 12, 1e18);
        vm.expectRevert("Incorrect number of events found");
        _getDefiBridgeProcessedData();
    }

    function testGetDefiBridgeProcessedDataIncorrectNumEventsNoEvent() public {
        vm.recordLogs();
        vm.expectRevert("Incorrect number of events found");
        _getDefiBridgeProcessedData();
    }

    function testGetDefiBridgeProcessedDataIncorrectNumEventsSyncAndAsync() public {
        vm.recordLogs();
        emit DefiBridgeProcessed(126, 12, 41, 9769836, 35345, true, "");
        emit AsyncDefiBridgeProcessed(126, 12, 1e18);
        emit AsyncDefiBridgeProcessed(126, 12, 1e18);
        emit DefiBridgeProcessed(12354, 354, 623, 26634, 6342, true, "");
        vm.expectRevert("Incorrect number of events found");
        _getDefiBridgeProcessedData();
    }

    function testRollupBeneficiaryEncoding() public {
        address beneficiary = 0x508383c4cbD351dC2d4F632C65Ee9d2BC79612EC;
        this.setRollupBeneficiary(beneficiary);
        uint256 bridgeCallData = encodeBridgeCallData(5, emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0);
        bytes memory proofData = _getProofData(bridgeCallData, 1e18);
        address decodedBeneficiary = _extractRollupBeneficiary(proofData);
        assertEq(decodedBeneficiary, beneficiary, "Decoded address does not match");
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

    // copied from Decoder.sol
    function _extractRollupBeneficiary(bytes memory _proofData) internal pure returns (address rollupBeneficiary) {
        assembly {
            rollupBeneficiary := mload(add(_proofData, ROLLUP_BENEFICIARY_OFFSET))
            // Validate `rollupBeneficiary` is an address
            if gt(rollupBeneficiary, ADDRESS_MASK) {
                revert(0, 0)
            }
        }
    }
}
