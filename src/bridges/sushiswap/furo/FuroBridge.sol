// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BridgeBase} from "../../base/BridgeBase.sol";
import {ErrorLib} from "../../base/ErrorLib.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

import {IRollupProcessor} from "../../../aztec/interfaces/IRollupProcessor.sol";

import {IFuroStream} from "../../../interfaces/sushiswap/furo/IFuroStream.sol";

contract FuroBridge is BridgeBase {
    IFuroStream public constant FURO = IFuroStream(0x4ab2FC6e258a0cA7175D05fF10C5cF798A672cAE);

    mapping(uint256 => uint256) public nonceToStream;

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

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
            bool
        )
    {
        if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL
        ) {
            outputValueA = _create(_inputAssetA, _inputValue, _interactionNonce, _auxData);
        } else if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20
        ) {
            outputValueA = _claim(_inputAssetA, _outputAssetA, _inputValue);
        } else {
            revert("Invalid");
        }
    }

    function preApprove(address _asset) public {
        address bentoBox = FURO.bentoBox();
        {
            (bool success, ) = bentoBox.call(
                abi.encodeWithSignature(
                    "setMasterContractApproval(address,address,bool,uint8,bytes32,bytes32)",
                    address(this),
                    address(FURO),
                    true,
                    0,
                    0,
                    0
                )
            );
            if (!success) {
                revert("Did not master approve");
            }
        }
        // TODO: Needs to be safeApprove to handle non-complient ERC20
        IERC20(_asset).approve(bentoBox, type(uint256).max);
        IERC20(_asset).approve(address(ROLLUP_PROCESSOR), type(uint256).max);
    }

    function _create(
        AztecTypes.AztecAsset calldata _inputAssetA,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64 _auxData
    ) internal returns (uint256) {
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

    function _claim(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata _outputAssetA,
        uint256 _inputValue
    ) internal returns (uint256) {
        (, address to) = FURO.withdrawFromStream(
            nonceToStream[_inputAssetA.id],
            _inputValue,
            address(this),
            false,
            bytes("")
        );

        if (to != address(this)) {
            revert("Recipient does not match");
        }

        // Bridge itself should never hold tokens unless mid-claim or mid-create so transferring all is fine
        return IERC20(_outputAssetA.erc20Address).balanceOf(address(this));
    }
}
