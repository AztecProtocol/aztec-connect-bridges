// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {AztecTypes} from "../../../lib/rollup-encoder/src/libraries/AztecTypes.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";

/**
 * @title Aztec Address Registry.
 * @author Josh Crites (@critesjosh on Github), Aztec team
 * @notice This contract can be used to anonymously register an ethereum address with an id.
 *         This is useful for reducing the amount of data required to pass an ethereum address through auxData.
 * @dev Use this contract to lookup ethereum addresses by id.
 */
contract AddressRegistry is BridgeBase {
    uint256 public addressCount;
    mapping(uint256 => address) public addresses;

    event AddressRegistered(uint256 indexed index, address indexed entity);

    /**
     * @notice Set address of rollup processor
     * @param _rollupProcessor Address of rollup processor
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    /**
     * @notice Function for getting VIRTUAL assets (step 1) to register an address and registering an address (step 2).
     * @dev This method can only be called from the RollupProcessor. The first step to register an address is for a user to
     * get the type(uint160).max value of VIRTUAL assets back from the bridge. The second step is for the user
     * to send an amount of VIRTUAL assets back to the bridge. The amount that is sent back is equal to the number of the
     * ethereum address that is being registered (e.g. uint160(0x2e782B05290A7fFfA137a81a2bad2446AD0DdFEB)).
     *
     * @param _inputAssetA - ETH (step 1) or VIRTUAL (step 2)
     * @param _outputAssetA - VIRTUAL (steps 1 and 2)
     * @param _totalInputValue - must be 1 wei (ETH) (step 1) or address value (step 2)
     * @return outputValueA - type(uint160).max (step 1) or 0 VIRTUAL (step 2)
     *
     */

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
        if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
            if (_totalInputValue != 1) {
                revert ErrorLib.InvalidInputAmount();
            }
            return (type(uint160).max, 0, false);
        } else if (_inputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL) {
            address toRegister = address(uint160(_totalInputValue));
            registerAddress(toRegister);
            return (0, 0, false);
        } else {
            revert ErrorLib.InvalidInput();
        }
    }

    /**
     * @notice Register an address at the registry
     * @dev This function can be called directly from another Ethereum account. This can be done in
     * one step, in one transaction. Coming from Ethereum directly, this method is not as privacy
     * preserving as registering an address through the bridge.
     *
     * @param _to - The address to register
     * @return addressCount - the index of address that has been registered
     */

    function registerAddress(address _to) public returns (uint256) {
        uint256 userIndex = addressCount++;
        addresses[userIndex] = _to;
        emit AddressRegistered(userIndex, _to);
        return userIndex;
    }
}