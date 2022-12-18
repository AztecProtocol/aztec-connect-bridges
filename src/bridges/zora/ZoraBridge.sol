// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";

/*
library AztecTypes {
    enum AztecAssetType {
        NOT_USED,
        ETH,
        ERC20,
        ERC721, <- need to add this.
        VIRTUAL
    }

    struct AztecAsset {
        uint256 id;
        address erc20Address;     <- need to rename this (no longer just erc-20).
        AztecAssetType assetType;
    }
}
*/

contract Zora is BridgeBase {
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata _inputAssetB,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _totalInputValue,
        uint256,
        uint64 _auxData,
        address
    ) external payable override (BridgeBase) onlyRollup returns (uint256 outputValueA, uint256, bool) {
        /*
        To fill an ask, we need Bob to authorize us to send ERC-20 tokens to Zora with this contract as the recipient.
        _inputAssetA:  ERC-20 token to pay for the Ask.
        _inputAssetB:  ERC-721 token the we want to fill the Ask of.
        _outputAssetA: Virtual token that corresponds to the ERC-721 token now owned by Aztec.

        Now construct the fillAsk request: https://docs.zora.co/docs/smart-contracts/modules/Asks/zora-v3-asks-v1.1#fillask,
        and call it on the zora contract.
        function fillAsk(
            address _tokenContract, <- _inputAssetB.address
            uint256 _tokenId,       <- _inputAssetB.id
            address _fillCurrency,  <- _inputAssetA.address
            uint256 _fillAmount,    <- _totalInputValue
            address _finder         <- 0x0000000000000000000000000000000000000000
        ) 

        Then we utilize the NFTVault bridge.
        virtualToken, _, _ = NftVault.convert(
            AztecTypes.AztecAsset calldata _inputAssetA,  <- ETH 
            AztecTypes.AztecAsset calldata,
            AztecTypes.AztecAsset calldata _outputAssetA, <- VIRTUAL
            AztecTypes.AztecAsset calldata,
            uint256 _totalInputValue,                     <- 1 WEI
            uint256,
            uint64,
            address
        )
        matchDeposit(
            uint256 _virtualAssetId, <- vitualToken.id
            address _collection,     <- inputAssetB.address
            uint256 _tokenId         <- inputAssetB.id
        )

        Lastly, we return the virtual token.
        return (1, 0, false)
        */
    }
}
