// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {AztecTypes} from "../../../lib/rollup-encoder/src/libraries/AztecTypes.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";

/**
 * @title
 * @author
 * @notice
 * @dev
 */
contract AddressRegistry is BridgeBase {
    uint64 public id;
    mapping(uint64 => address) public addresses;
    uint256 public MAX_INT =
        0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;

    event AddressRegistered(
        uint64 indexed id,
        address indexed registeredAddress
    );

    /**
     * @notice Set address of rollup processor
     * @param _rollupProcessor Address of rollup processor
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _totalInputValue,
        uint256,
        uint64,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (uint256 outputValueA, uint256, bool)
    {
        if (
            _inputAssetA.assetType != AztecTypes.AztecAssetType.NOT_USED ||
            _inputAssetA.assetType != AztecTypes.AztecAssetType.VIRTUAL
        ) revert ErrorLib.InvalidInputA();
        if (_outputAssetA.assetType != AztecTypes.AztecAssetType.VIRTUAL)
            revert ErrorLib.InvalidOutputA();

        // get virtual assets
        if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.NOT_USED &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL
        ) {
            return (MAX_INT, 0, false);
        }
        // register address with virtual asset
        else if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL
        ) {
            address toRegister = address(uint160(_totalInputValue));
            addresses[id] = toRegister;
            emit AddressRegistered(id, toRegister);
            id++;
            return (0, 0, false);
        } else {
            revert();
        }
    }
}
