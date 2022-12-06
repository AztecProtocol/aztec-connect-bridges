// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC721} from "../../../lib/openzeppelin-contracts/contracts/interfaces/IERC721.sol";
import {AztecTypes} from "../../../lib/rollup-encoder/src/libraries/AztecTypes.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {AddressRegistry} from "../registry/AddressRegistry.sol";

/**
 * @title Basic NFT Vault for Aztec.
 * @author Aztec Team
 * @notice You can use this contract to hold your NFTs on Aztec. Whoever holds the corresponding virutal asset note can withdraw the NFT.
 * @dev This bridge demonstrates basic functionality for an NFT bridge. This may be extended to support more features.
 */
contract NftVault is BridgeBase {
    struct NftAsset {
        address collection;
        uint256 id;
    }

    mapping(uint256 => NftAsset) public tokens;
    AddressRegistry public immutable registry;

    constructor(address _rollupProcessor, address _registry) BridgeBase(_rollupProcessor) {
        registry = AddressRegistry(_registry);
    }

    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _totalInputValue,
        uint256,
        uint64 _auxData,
        address
    )
        external
        payable
        override (
            // uint64 _auxData,
            // address _rollupBeneficiary
            BridgeBase
        )
        onlyRollup
        returns (uint256 outputValueA, uint256 outputValueB, bool isAsync)
    {
        if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.NOT_USED
                || _inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20
        ) revert ErrorLib.InvalidInputA();
        if (
            _outputAssetA.assetType == AztecTypes.AztecAssetType.NOT_USED
                || _outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20
        ) revert ErrorLib.InvalidOutputA();
        if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH
                && _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL
        ) {
            require(_totalInputValue == 1, "send only 1 wei");
            return (1, 0, false);
        } else if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL
                && _outputAssetA.assetType == AztecTypes.AztecAssetType.ETH
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

    function matchDeposit(uint256 _virtualAssetId, address _collection, uint256 _tokenId) external {
        require(tokens[_virtualAssetId].collection == address(0x0), "Asset registered");
        tokens[_virtualAssetId] = NftAsset({collection: _collection, id: _tokenId});
        IERC721(_collection).transferFrom(msg.sender, address(this), _tokenId);
    }
}
