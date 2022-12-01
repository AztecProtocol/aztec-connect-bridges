// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC721} from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";
import {AztecTypes} from "../../../lib/rollup-encoder/src/libraries/AztecTypes.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {AddressRegistry} from "../registry/AddressRegistry.sol";

/**
 * @title An example bridge contract.
 * @author Aztec Team
 * @notice You can use this contract to immediately get back what you've deposited.
 * @dev This bridge demonstrates the flow of assets in the convert function. This bridge simply returns what has been
 *      sent to it.
 */
contract NftVault is BridgeBase {
    struct NftAsset {
        address collection;
        uint256 id;
    }
    mapping(uint256 => NftAsset) public tokens;

    AddressRegistry public registry = AddressRegistry(address(0x0));

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _totalInputValue,
        uint256 _interactionNonce,
        uint64 _auxData,
        address
    )
        external
        payable
        override(
            // uint64 _auxData,
            // address _rollupBeneficiary
            BridgeBase
        )
        onlyRollup
        returns (uint256 outputValueA, uint256 outputValueB, bool isAsync)
    {
        // DEPOSIT
        // return virutal asset id, will not actually match to NFT until matchDeposit is called from ethereum
        if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL
        ) {
            require(_totalInputValue == 1, "send only 1 wei");
            tokens[_interactionNonce] = NftAsset({
                collection: address(0x0),
                id: 0
            });
            return (1, 0, false);
        }
        // WITHDRAW
        else if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL
        ) {
            NftAsset memory token = tokens[_inputAssetA.id];
            require(token.collection != address(0x0), "NFT doesn't exist");

            address _to = registry.addresses(_auxData);
            require(_to != address(0x0), "unregistered withdraw address");

            IERC721(token.collection).transferFrom(address(this), _to, token.id);
            delete tokens[_inputAssetA.id];
            return (0, 0, false);
        }
    }

    function matchDeposit(
        uint256 _virtualAssetId,
        address _collection,
        address _from,
        uint256 _tokenId
    ) external {
        NftAsset memory asset = tokens[_virtualAssetId];
        require(asset.collection == address(0x0), "Asset registered");
        IERC721(_collection).transferFrom(_from, address(this), _tokenId);
        tokens[_virtualAssetId] = NftAsset({
            collection: _collection,
            id: _tokenId
        });
    }
}
