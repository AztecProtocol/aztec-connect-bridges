// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.0 <=0.8.10;
pragma abicoder v2;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDefiBridge} from "../../interfaces/IDefiBridge.sol";
import {AztecTypes} from "../../aztec/AztecTypes.sol";
import "../../interfaces/IRollupProcessor.sol";
import "./interfaces/ICERC20.sol";
import "./interfaces/ICETH.sol";

/**
 * @title Aztec Connect Bridge for Compound protocol
 * @notice You can use this contract to mint or redeem cTokens.
 * @dev Implementation of the IDefiBridge interface for cTokens.
 */
contract CompoundBridge is IDefiBridge {
    using SafeERC20 for IERC20;

    address public immutable rollupProcessor;

    error InvalidCaller();
    error IncorrectInputAsset();
    error IncorrectOutputAsset();
    error IncorrectAuxData();
    error AsyncModeDisabled();

    constructor(address _rollupProcessor) {
        rollupProcessor = _rollupProcessor;
    }

    receive() external payable {}

    /**
     * @notice Function which mints and burns cTokens in echange for the underlying asset.
     * @dev This method can only be called from RollupProcessor.sol. If auxData is 0 the mint flow is executed,
     * if 1 deposit flow.
     *
     * @param inputAssetA - ETH or ERC20 (Mint) or cToken ERC20 (Redeem)
     * @param outputAssetA - cToken (Mint) or ETH or ERC20 (Redeem)
     * @param totalInputValue - the amount of token or ETH deposit (Mint), the amount of cToken to burn (Redeem)
     * @param auxData - 0 (Mint), 1 (Redeem)
     * @return outputValueA - the amount of cToken (Mint) or ETH/ERC20 (redeem) transferred to RollupProcessor.sol
     */
    function convert(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 totalInputValue,
        uint256 interactionNonce,
        uint64 auxData,
        address
    )
        external
        payable
        override
        returns (
            uint256 outputValueA,
            uint256,
            bool
        )
    {
        if (msg.sender != rollupProcessor) revert InvalidCaller();

        if (auxData == 0) {
            // mint
            if (outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert IncorrectOutputAsset();

            if (inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                ICETH cToken = ICETH(outputAssetA.erc20Address);
                cToken.mint{value: msg.value}();
                outputValueA = cToken.balanceOf(address(this));
                cToken.approve(rollupProcessor, outputValueA);
            } else if (inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
                IERC20 tokenIn = IERC20(inputAssetA.erc20Address);
                ICERC20 tokenOut = ICERC20(outputAssetA.erc20Address);
                tokenIn.safeIncreaseAllowance(address(tokenOut), totalInputValue);
                tokenOut.mint(totalInputValue);
                outputValueA = tokenOut.balanceOf(address(this));
                tokenOut.approve(rollupProcessor, outputValueA);
            } else {
                revert IncorrectInputAsset();
            }
        } else if (auxData == 1) {
            // redeem
            if (inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert IncorrectInputAsset();

            if (outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                // redeem cETH case
                ICETH cToken = ICETH(inputAssetA.erc20Address);
                cToken.redeem(totalInputValue);
                outputValueA = address(this).balance;
                IRollupProcessor(rollupProcessor).receiveEthFromBridge{value: outputValueA}(interactionNonce);
            } else if (outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
                ICERC20 tokenIn = ICERC20(inputAssetA.erc20Address);
                IERC20 tokenOut = IERC20(outputAssetA.erc20Address);
                tokenIn.redeem(totalInputValue);
                outputValueA = tokenOut.balanceOf(address(this));
                tokenOut.safeIncreaseAllowance(rollupProcessor, outputValueA);
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
        returns (
            uint256,
            uint256,
            bool
        )
    {
        revert AsyncModeDisabled();
    }
}
