// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.0 <=0.8.10;
pragma abicoder v2;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDefiBridge} from "../../interfaces/IDefiBridge.sol";
import {AztecTypes} from "../../aztec/AztecTypes.sol";
import "../../interfaces/IRollupProcessor.sol";

import "../../test/console.sol";

interface ICETH {
    function approve(address, uint256) external returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function transfer(address, uint256) external returns (uint256);

    function mint() external payable;

    function redeem(uint256) external returns (uint256);

    function redeemUnderlying(uint256) external returns (uint256);
}

interface ICERC20 {
    function accrueInterest() external;

    function approve(address, uint256) external returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function balanceOfUnderlying(address) external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function transfer(address, uint256) external returns (uint256);

    function mint(uint256) external returns (uint256);

    function redeem(uint256) external returns (uint256);

    function redeemUnderlying(uint256) external returns (uint256);

    function underlying() external returns (address);
}

contract CompoundBridge is IDefiBridge {
    address public immutable rollupProcessor;

    error InvalidCaller();
    error IncorrectInputAsset();
    error IncorrectOutputAsset();
    error IncorrectAuxData();
    error AsyncModeDisabled();

    constructor(address _rollupProcessor) public {
        rollupProcessor = _rollupProcessor;
    }

    receive() external payable {}

    // ATC: To do: extend bridge to handle borrows and repays
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
                tokenIn.approve(address(tokenOut), totalInputValue);
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
                tokenOut.approve(rollupProcessor, outputValueA);
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
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 interactionNonce,
        uint64
    )
        external
        payable
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool interactionComplete
        )
    {
        revert AsyncModeDisabled();
    }
}
