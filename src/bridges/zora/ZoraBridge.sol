// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {AddressRegistry} from "../registry/AddressRegistry.sol";

// Get function definition from: https://github.com/ourzora/v3/blob/1d4c0c951ccd5c1d446283ce6fef3757ad97b804/contracts/modules/Asks/V1.1/AsksV1_1.sol#L302.
contract ZoraAsk {
    function fillAsk(
        address _tokenContract,
        uint256 _tokenId,
        address _fillCurrency,
        uint256 _fillAmount,
        address _finder
    ) external {}
}

contract ZoraBridge is BridgeBase {
    struct NftAsset {
        address collection;
        uint256 tokenId;
    }
    // Holds the VIRTUAL token -> NFT relationship.
    mapping(uint256 => NftAsset) public nftAssets;

    // Other contracts.
    ZoraAsk internal za;
    AddressRegistry public immutable registry;

    // Need to pass the zora & registry addresses to construct the bridge.
    constructor(address _rollupProcessor, address _zora, address _registry) BridgeBase(_rollupProcessor) {
        za = ZoraAsk(_zora);
        registry = AddressRegistry(_registry);
    }

    // Converts ETH into a virtual token by filling an ask on the Zora contract.
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _totalInputValue,
        uint256 _interactionNonce,
        uint64 _auxData,
        address
    ) external payable override (BridgeBase) onlyRollup returns (uint256 outputValueA, uint256 outputValueB, bool async) {
        // Add error handling for input/output types.

        if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ETH &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL) {

            // Split _auxData into halves. 
            // First half is used to get the collection address from the registry.
            // Second half is the tokenId.
            uint256 _firstHalfAux = _auxData & 0xffffffff;
            uint256 _secondHalfAux = _auxData >> 32;

            address collection = registry.addresses(_firstHalfAux);
            // Add error handling for if the NFT is not in the map. 
            za.fillAsk(
                collection,
                _secondHalfAux,
                address(0x0),     // 0 address to indicate this sale is in ETH.
                _totalInputValue, // Use the total input value to specify how much ETH to fill the ask with.
                address(0x0)      // Leave the finder address empty.
            );

            // Update the mapping with the virtual token Id.
            nftAssets[_interactionNonce] = NftAsset({
                collection: collection,
                tokenId: _secondHalfAux
            });

            // Return the virtual token.
            return (1, 0, false);
        }
    }
}
