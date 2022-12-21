// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";

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
    struct ZoraNFT {
        address collection;
        uint256 tokenId;
    }

    uint64 internal zoraNFTCount;
    mapping(uint64 => ZoraNFT) internal zoraNFTs;
    ZoraAsk internal za;

    // Need to pass the zora contract address to construct the bridge.
    constructor(address _rollupProcessor, address _zora) BridgeBase(_rollupProcessor) {
        za = ZoraAsk(_zora);
    }

    // Converts ETH into a virtual token by filling an ask on the Zora contract.
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _totalInputValue,
        uint256,
        uint64 _auxData,
        address
    ) external payable override (BridgeBase) onlyRollup returns (uint256 outputValueA, uint256 outputValueB, bool async) {
        // Add error handling for input/output types.

        if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ETH &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL) {

            // Look up the NFT details using the _auxData.
            ZoraNFT memory nft = zoraNFTs[_auxData];

            // Add error handling for if the NFT is not in the map. 
            za.fillAsk(
                nft.collection,
                nft.tokenId,
                address(0x0),     // 0 address to indicate this sale is in ETH.
                _totalInputValue, // Use the total input value to specify how much ETH to fill the ask with.
                address(0x0)      // Leave the finder address empty.
            );
            // Return a virtual token.
            return (1, 0, false);
        }
    }

    // A function to register the details of a Zora NFT.
    function registerZoraNFT(address _collection, uint256 _tokenId) public returns (uint64) {
        uint64 newIndex = zoraNFTCount++;
        zoraNFTs[newIndex] = ZoraNFT({
            collection: _collection,
            tokenId: _tokenId
        });
        return newIndex;
    }
}
