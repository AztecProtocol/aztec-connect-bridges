// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";

import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";

import {IFuroStream} from "../../interfaces/sushiswap/furo/IFuroStream.sol";

contract FuroBridge is BridgeBase {
    IFuroStream public immutable FURO;

    mapping(uint256 => uint256) public nonceToStream;

    constructor(address _rollupProcessor, address _furo) BridgeBase(_rollupProcessor) {
        FURO = IFuroStream(_furo);
    }

    receive() external payable {}

    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64 _auxData,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256,
            bool isAsync
        )
    {}

    function _create(
        AztecTypes.AztecAsset calldata _inputAssetA,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64 _auxData
    ) public returns (uint256) {
        (uint256 streamId, uint256 depositedShares) = FURO.createStream(
            address(this),
            _inputAssetA.erc20Address,
            uint64(_auxData >> 32),
            uint64(uint32(_auxData)),
            _inputValue,
            false
        );
        nonceToStream[_interactionNonce] = streamId;
        return depositedShares;
    }

    function _claim(AztecTypes.AztecAsset calldata _inputAssetA, uint256 _inputValue) public returns (uint256) {
        (uint256 recipientBalance, address to) = FURO.withdrawFromStream(
            nonceToStream[_inputAssetA.id],
            _inputValue,
            address(this),
            false,
            bytes("")
        );

        if (to != address(this)) {
            revert("Recipient does not match");
        }

        return recipientBalance;
    }
}
