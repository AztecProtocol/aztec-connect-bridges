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
 * @author Josh Crites, (@critesjosh on Github),  Aztec Team
 * @notice You can use this contract to hold your NFTs on Aztec. Whoever holds the corresponding virutal asset note can withdraw the NFT.
 * @dev This bridge demonstrates basic functionality for an NFT bridge. This may be extended to support more features.
 */
contract NFTVault is BridgeBase {
    struct NFTAsset {
        address collection;
        uint256 tokenId;
    }

    AddressRegistry public immutable REGISTRY;

    mapping(uint256 => NFTAsset) public nftAssets;

    error InvalidVirtualAssetId();

    event NFTDeposit(uint256 indexed virtualAssetId, address indexed collection, uint256 indexed tokenId);
    event NFTWithdraw(uint256 indexed virtualAssetId, address indexed collection, uint256 indexed tokenId);

    /**
     * @notice Set the addresses of RollupProcessor and AddressRegistry
     * @param _rollupProcessor Address of the RollupProcessor
     * @param _registry Address of the AddressRegistry
     */
    constructor(address _rollupProcessor, address _registry) BridgeBase(_rollupProcessor) {
        REGISTRY = AddressRegistry(_registry);
    }

    /**
     * @notice Function for the first step of a NFT deposit, a NFT withdrawal, or transfer to another NFTVault.
     * @dev This method can only be called from the RollupProcessor. The first step of the
     * deposit flow returns a virutal asset note that will represent the NFT on Aztec. After the
     * virutal asset note is received on Aztec, the user calls matchAndPull which deposits the NFT
     * into Aztec and matches it with the virtual asset. When the virutal asset is sent to this function
     * it is burned and the NFT is sent to the recipient passed in _auxData.
     *
     * @param _inputAssetA - ETH (Deposit) or VIRTUAL (Withdrawal)
     * @param _outputAssetA - VIRTUAL (Deposit) or 0 ETH (Withdrawal)
     * @param _totalInputValue - must be 1 wei (Deposit) or 1 VIRTUAL (Withdrawal)
     * @param _interactionNonce - A globally unique identifier of this interaction/`convert(...)` call
     *                              corresponding to the returned virtual asset id
     * @param _auxData - corresponds to the Ethereum address id in the AddressRegistry.sol for withdrawals
     * @return outputValueA - 1 VIRTUAL asset (Deposit) or 0 ETH (Withdrawal)
     *
     */

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
        override (BridgeBase)
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
        if (_totalInputValue != 1) {
            revert ErrorLib.InvalidInputAmount();
        }
        if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH
                && _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL
        ) {
            return (1, 0, false);
        } else if (_inputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL) {
            NFTAsset memory token = nftAssets[_inputAssetA.id];
            if (token.collection == address(0x0)) {
                revert ErrorLib.InvalidInputA();
            }

            address to = REGISTRY.addresses(_auxData);
            if (to == address(0x0)) {
                revert ErrorLib.InvalidAuxData();
            }
            delete nftAssets[_inputAssetA.id];
            emit NFTWithdraw(_inputAssetA.id, token.collection, token.tokenId);

            if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                IERC721(token.collection).transferFrom(address(this), to, token.tokenId);
                return (0, 0, false);
            } else {
                IERC721(token.collection).approve(to, token.tokenId);
                NFTVault(to).matchAndPull(_interactionNonce, token.collection, token.tokenId);
                return (1, 0, false);
            }
        }
    }

    /**
     * @notice Function for the second step of a NFT deposit or for transfers from other NFTVaults.
     * @dev For a deposit, this method is called by an Ethereum L1 account that owns the NFT to deposit.
     * The user must approve this bridge contract to transfer the users NFT before this function
     * is called. This function assumes the NFT contract complies with the ERC721 standard.
     * For a transfer from another NFTVault, this method is called by the NFTVault that is sending the NFT.
     *
     * @param _virtualAssetId - the virutal asset id of the note returned in the deposit step of the convert function
     * @param _collection - collection address of the NFT
     * @param _tokenId - the token id of the NFT
     */

    function matchAndPull(uint256 _virtualAssetId, address _collection, uint256 _tokenId) external {
        if (nftAssets[_virtualAssetId].collection != address(0x0)) {
            revert InvalidVirtualAssetId();
        }
        nftAssets[_virtualAssetId] = NFTAsset({collection: _collection, tokenId: _tokenId});
        IERC721(_collection).transferFrom(msg.sender, address(this), _tokenId);
        emit NFTDeposit(_virtualAssetId, _collection, _tokenId);
    }
}
