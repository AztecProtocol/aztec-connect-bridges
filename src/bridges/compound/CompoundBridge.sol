// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDefiBridge} from "../../interfaces/IDefiBridge.sol";
import {AztecTypes} from "../../aztec/AztecTypes.sol";
import {IRollupProcessor} from "../../interfaces/IRollupProcessor.sol";
import {ICERC20} from "./interfaces/ICERC20.sol";
import {ICETH} from "./interfaces/ICETH.sol";

/**
 * @title Aztec Connect Bridge for Compound protocol
 * @notice You can use this contract to mint or redeem cTokens.
 * @dev Implementation of the IDefiBridge interface for cTokens.
 */
contract CompoundBridge is IDefiBridge {
    using SafeERC20 for IERC20;

    error InvalidCaller();
    error IncorrectInputAsset();
    error IncorrectOutputAsset();
    error IncorrectAuxData();
    error AsyncModeDisabled();

    address public immutable ROLLUP_PROCESSOR;

    /**
     * @notice Set the address of RollupProcessor.sol
     * @param _rollupProcessor Address of RollupProcessor.sol
     */
    constructor(address _rollupProcessor) {
        ROLLUP_PROCESSOR = _rollupProcessor;
    }

    receive() external payable {}

    /**
     * @notice Function which mints and burns cTokens in an exchange for the underlying asset.
     * @dev This method can only be called from RollupProcessor.sol. If `_auxData` is 0 the mint flow is executed,
     * if 1 redeem flow.
     *
     * @param _inputAssetA - ETH/ERC20 (Mint), cToken ERC20 (Redeem)
     * @param _outputAssetA - cToken (Mint), ETH/ERC20 (Redeem)
     * @param _totalInputValue - the amount of ERC20 token/ETH to deposit (Mint), the amount of cToken to burn (Redeem)
     * @param _interactionNonce - interaction nonce as defined in RollupProcessor.sol
     * @param _auxData - 0 (Mint), 1 (Redeem)
     * @return outputValueA - the amount of cToken (Mint) or ETH/ERC20 (Redeem) transferred to RollupProcessor.sol
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
        override(IDefiBridge)
        returns (
            uint256 outputValueA,
            uint256,
            bool
        )
    {
        if (msg.sender != ROLLUP_PROCESSOR) revert InvalidCaller();

        if (_auxData == 0) {
            // Mint
            if (_outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert IncorrectOutputAsset();

            if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                ICETH cToken = ICETH(_outputAssetA.erc20Address);
                cToken.mint{value: msg.value}();
                outputValueA = cToken.balanceOf(address(this));
                cToken.approve(ROLLUP_PROCESSOR, outputValueA);
            } else if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
                IERC20 tokenIn = IERC20(_inputAssetA.erc20Address);
                ICERC20 tokenOut = ICERC20(_outputAssetA.erc20Address);
                // Using safeIncreaseAllowance(...) instead of approve(...) here because tokenIn can be Tether
                tokenIn.safeIncreaseAllowance(address(tokenOut), _totalInputValue);
                tokenOut.mint(_totalInputValue);
                outputValueA = tokenOut.balanceOf(address(this));
                tokenOut.approve(ROLLUP_PROCESSOR, outputValueA);
            } else {
                revert IncorrectInputAsset();
            }
        } else if (_auxData == 1) {
            // Redeem
            if (_inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert IncorrectInputAsset();

            if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                // Redeem cETH case
                ICETH cToken = ICETH(_inputAssetA.erc20Address);
                cToken.redeem(_totalInputValue);
                outputValueA = address(this).balance;
                IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(_interactionNonce);
            } else if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
                ICERC20 tokenIn = ICERC20(_inputAssetA.erc20Address);
                IERC20 tokenOut = IERC20(_outputAssetA.erc20Address);
                tokenIn.redeem(_totalInputValue);
                outputValueA = tokenOut.balanceOf(address(this));
                // Using safeIncreaseAllowance(...) instead of approve(...) here because tokenOut can be Tether
                tokenOut.safeIncreaseAllowance(ROLLUP_PROCESSOR, outputValueA);
            } else {
                revert IncorrectOutputAsset();
            }
        } else {
            revert IncorrectAuxData();
        }
    }

    function finalise(
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        uint256,
        uint64
    )
        external
        payable
        override(IDefiBridge)
        returns (
            uint256,
            uint256,
            bool
        )
    {
        revert AsyncModeDisabled();
    }
}
