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
     * @dev This method can only be called from RollupProcessor.sol. If auxData is 0 the mint flow is executed,
     * if 1 redeem flow.
     *
     * @param inputAssetA - ETH/ERC20 (Mint), cToken ERC20 (Redeem)
     * @param outputAssetA - cToken (Mint), ETH/ERC20 (Redeem)
     * @param totalInputValue - the amount of ERC20 token/ETH to deposit (Mint), the amount of cToken to burn (Redeem)
     * @param interactionNonce - interaction nonce as defined in RollupProcessor.sol
     * @param auxData - 0 (Mint), 1 (Redeem)
     * @return outputValueA - the amount of cToken (Mint) or ETH/ERC20 (Redeem) transferred to RollupProcessor.sol
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
        if (msg.sender != ROLLUP_PROCESSOR) revert InvalidCaller();

        if (auxData == 0) {
            // Mint
            if (outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert IncorrectOutputAsset();

            if (inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                ICETH cToken = ICETH(outputAssetA.erc20Address);
                cToken.mint{value: msg.value}();
                outputValueA = cToken.balanceOf(address(this));
                cToken.approve(ROLLUP_PROCESSOR, outputValueA);
            } else if (inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
                IERC20 tokenIn = IERC20(inputAssetA.erc20Address);
                ICERC20 tokenOut = ICERC20(outputAssetA.erc20Address);
                // Using safeIncreaseAllowance(...) instead of approve(...) here because tokenIn can be Tether
                tokenIn.safeIncreaseAllowance(address(tokenOut), totalInputValue);
                tokenOut.mint(totalInputValue);
                outputValueA = tokenOut.balanceOf(address(this));
                tokenOut.approve(ROLLUP_PROCESSOR, outputValueA);
            } else {
                revert IncorrectInputAsset();
            }
        } else if (auxData == 1) {
            // Redeem
            if (inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert IncorrectInputAsset();

            if (outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                // Redeem cETH case
                ICETH cToken = ICETH(inputAssetA.erc20Address);
                cToken.redeem(totalInputValue);
                outputValueA = address(this).balance;
                IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(interactionNonce);
            } else if (outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
                ICERC20 tokenIn = ICERC20(inputAssetA.erc20Address);
                IERC20 tokenOut = IERC20(outputAssetA.erc20Address);
                tokenIn.redeem(totalInputValue);
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
        returns (
            uint256,
            uint256,
            bool
        )
    {
        revert AsyncModeDisabled();
    }
}
