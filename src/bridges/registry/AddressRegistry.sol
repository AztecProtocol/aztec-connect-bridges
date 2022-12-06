// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {AztecTypes} from "../../../lib/rollup-encoder/src/libraries/AztecTypes.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";

/**
 * @title Aztec Address Registry.
 * @author Aztec Team
 * @notice This contract can be used to anonymously register an ethereum address with an id.
 *         This is useful for reducing the amount of data required to pass an ethereum address through auxData.
 * @dev Use this contract to lookup ethereum addresses by id.
 */
contract AddressRegistry is BridgeBase {
    uint64 public addressCount;
    mapping(uint256 => address) public addresses;

    event AddressRegistered(uint256 indexed addressCount, address indexed registeredAddress);

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
    ) external payable override (BridgeBase) onlyRollup returns (uint256 outputValueA, uint256, bool) {
        if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.NOT_USED
                || _inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20
        ) revert ErrorLib.InvalidInputA();
        if (_outputAssetA.assetType != AztecTypes.AztecAssetType.VIRTUAL) {
            revert ErrorLib.InvalidOutputA();
        }
        if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH
                && _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL
        ) {
            require(_totalInputValue == 1, "send only 1 wei");
            return (type(uint160).max, 0, false);
        }
        else if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL
                && _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL
        ) {
            addressCount++;
            address toRegister = address(uint160(_totalInputValue));
            addresses[addressCount] = toRegister;
            emit AddressRegistered(addressCount, toRegister);
            return (0, 0, false);
        } else {
            revert();
        }
    }

    function registerWithdrawAddress(address _to) external returns (uint256) {
        addressCount++;
        addresses[addressCount] = _to;
        emit AddressRegistered(addressCount, _to);
        return addressCount;
    }
}
