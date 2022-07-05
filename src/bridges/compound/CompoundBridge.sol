// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";

import {ErrorLib} from "./../base/ErrorLib.sol";
import {BridgeBase} from "./../base/BridgeBase.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";

import {IComptroller} from "../../interfaces/compound/IComptroller.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICERC20} from "../../interfaces/compound/ICERC20.sol";
import {ICETH} from "../../interfaces/compound/ICETH.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title Aztec Connect Bridge for Compound protocol
 * @notice You can use this contract to mint or redeem cTokens.
 * @dev Implementation of the IDefiBridge interface for cTokens.
 */
contract CompoundBridge is BridgeBase {
    using SafeERC20 for IERC20;

    error MarketNotListed();

    IComptroller public immutable COMPTROLLER = IComptroller(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
    // solhint-disable-next-line
    address public constant cETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    /**
     * @notice Set the address of RollupProcessor.sol
     * @param _rollupProcessor Address of RollupProcessor.sol
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    receive() external payable {}

    /**
     * @notice Set all the necessary approvals for a given cToken and its underlying.
     * @param _cToken - cToken address
     */
    function preApprove(address _cToken) external {
        (bool isListed, , ) = COMPTROLLER.markets(_cToken);
        if (!isListed) revert MarketNotListed();
        _preApprove(ICERC20(_cToken));
    }

    /**
     * @notice Set all the necessary approvals for all the cTokens registered in Comptroller.
     */
    function preApproveAll() external {
        address[] memory cTokens = COMPTROLLER.getAllMarkets();
        uint256 numMarkets = cTokens.length;
        for (uint256 i; i < numMarkets; ) {
            _preApprove(ICERC20(cTokens[i]));
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Function which mints and burns cTokens in an exchange for the underlying asset.
     * @dev This method can only be called from RollupProcessor.sol. If `_auxData` is 0 the mint flow is executed,
     * if 1 redeem flow.
     *
     * @param _inputAssetA - ETH/ERC20 (Mint), cToken ERC20 (Redeem)
     * @param _outputAssetA - cToken (Mint), ETH/ERC20 (Redeem)
     * @param _inputValue - the amount of ERC20 token/ETH to deposit (Mint), the amount of cToken to burn (Redeem)
     * @param _interactionNonce - interaction nonce as defined in RollupProcessor.sol
     * @param _auxData - 0 (Mint), 1 (Redeem)
     * @return outputValueA - the amount of cToken (Mint) or ETH/ERC20 (Redeem) transferred to RollupProcessor.sol
     */
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
        if (_auxData == 0) {
            // Mint
            if (_outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert ErrorLib.InvalidOutputA();

            if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                ICETH cToken = ICETH(_outputAssetA.erc20Address);
                cToken.mint{value: msg.value}();
                outputValueA = cToken.balanceOf(address(this));
            } else if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
                ICERC20 tokenOut = ICERC20(_outputAssetA.erc20Address);
                tokenOut.mint(_inputValue);
                outputValueA = tokenOut.balanceOf(address(this));
            } else {
                revert ErrorLib.InvalidInputA();
            }
        } else if (_auxData == 1) {
            // Redeem
            if (_inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert ErrorLib.InvalidInputA();

            if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                // Redeem cETH case
                ICETH cToken = ICETH(_inputAssetA.erc20Address);
                cToken.redeem(_inputValue);
                outputValueA = address(this).balance;
                IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(_interactionNonce);
            } else if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
                ICERC20 tokenIn = ICERC20(_inputAssetA.erc20Address);
                IERC20 tokenOut = IERC20(_outputAssetA.erc20Address);
                tokenIn.redeem(_inputValue);
                outputValueA = tokenOut.balanceOf(address(this));
            } else {
                revert ErrorLib.InvalidInputA();
            }
        } else {
            revert ErrorLib.InvalidAuxData();
        }
    }

    function _preApprove(ICERC20 _cToken) private {
        uint256 allowance = _cToken.allowance(address(this), ROLLUP_PROCESSOR);
        if (allowance < type(uint256).max) {
            _cToken.approve(ROLLUP_PROCESSOR, type(uint256).max - allowance);
        }
        if (address(_cToken) != cETH) {
            IERC20 underlying = IERC20(_cToken.underlying());
            // Using safeApprove(...) instead of approve(...) here because underlying can be Tether;
            allowance = underlying.allowance(address(this), address(_cToken));
            if (allowance != type(uint256).max) {
                // Resetting allowance to 0 in order to avoid issues with USDT
                underlying.safeApprove(address(_cToken), 0);
                underlying.safeApprove(address(_cToken), type(uint256).max);
            }
            allowance = underlying.allowance(address(this), ROLLUP_PROCESSOR);
            if (allowance != type(uint256).max) {
                // Resetting allowance to 0 in order to avoid issues with USDT
                underlying.safeApprove(ROLLUP_PROCESSOR, 0);
                underlying.safeApprove(ROLLUP_PROCESSOR, type(uint256).max);
            }
        }
    }
}
