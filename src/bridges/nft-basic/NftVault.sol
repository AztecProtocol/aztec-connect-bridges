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
contract NftVault is BridgeBase {
    struct NftAsset {
        address collection;
        uint256 id;
    }

    mapping(uint256 => NftAsset) public tokens;
    AddressRegistry public immutable REGISTRY;

    event NftDeposit(
        uint256 indexed virtualAssetId,
        address indexed collection,
        uint256 indexed tokenId
    );
    event NftWithdraw(
        uint256 indexed virtualAssetId,
        address indexed collection,
        uint256 indexed tokenId
    );

    /**
     * @notice Set the addresses of RollupProcessor.sol and AddressRegistry.sol
     * @param _rollupProcessor Address of the RollupProcessor.sol
     * @param _registry Address of the AddressRegistry.sol
     */
    constructor(
        address _rollupProcessor,
        address _registry
    ) BridgeBase(_rollupProcessor) {
        REGISTRY = AddressRegistry(_registry);
    }

    /**
     * @notice Function for the first step of a NFT deposit, or a NFT withdrawal.
     * @dev This method can only be called from the RollupProcessor.sol. The first step of the
     * deposit flow returns a virutal asset note that will represent the NFT on Aztec. After the
     * virutal asset note is received on Aztec, the user calls matchDeposit which deposits the NFT
     * into Aztec and matches it with the virtual asset. When the virutal asset is sent to this function
     * it is burned and the NFT is sent to the user (withdraw).
     *
     * @param _inputAssetA - ETH (Deposit) or VIRTUAL (Withdrawal)
     * @param _outputAssetA - VIRTUAL (Deposit) or 0 ETH (Withdrawal)
     * @param _totalInputValue - must be 1 wei (Deposit) or 1 VIRTUAL (Withdrawal)
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
        uint256,
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
        if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.NOT_USED ||
            _inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20
        ) revert ErrorLib.InvalidInputA();
        if (
            _outputAssetA.assetType == AztecTypes.AztecAssetType.NOT_USED ||
            _outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20
        ) revert ErrorLib.InvalidOutputA();
        if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL
        ) {
            if(_totalInputValue != 1 wei)
                revert ErrorLib.InvalidInputAmount();
            return (1, 0, false);
        } else if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.ETH
        ) {
            NftAsset memory token = tokens[_inputAssetA.id];
            if (token.collection == address(0x0))
                revert ErrorLib.InvalidInputA();

            address _to = REGISTRY.addresses(_auxData);
            if(_to == address(0x0))
                revert ErrorLib.InvalidAuxData();

            IERC721(token.collection).transferFrom(
                address(this),
                _to,
                token.id
            );
            emit NftWithdraw(_inputAssetA.id, token.collection, token.id);
            delete tokens[_inputAssetA.id];
            return (0, 0, false);
        }
    }

    /**
     * @notice Function for the second step of a NFT deposit.
     * @dev This method is called by an Ethereum L1 account that owns the NFT to deposit.
     * The user must approve this bridge contract to transfer the users NFT before this function
     * is called. This function assumes the NFT contract complies with the ERC721 standard.
     *
     * @param _virtualAssetId - the virutal asset id of the note returned in the deposit step of the convert function
     * @param _collection - collection address of the NFT
     * @param _tokenId - the token id of the NFT
     */

    function matchDeposit(
        uint256 _virtualAssetId,
        address _collection,
        uint256 _tokenId
    ) external {
        if(tokens[_virtualAssetId].collection != address(0x0))
            revert ErrorLib.InvalidVirtualAsset();
        tokens[_virtualAssetId] = NftAsset({
            collection: _collection,
            id: _tokenId
        });
        IERC721(_collection).transferFrom(msg.sender, address(this), _tokenId);
        emit NftDeposit(_virtualAssetId, _collection, _tokenId);
    }
}
