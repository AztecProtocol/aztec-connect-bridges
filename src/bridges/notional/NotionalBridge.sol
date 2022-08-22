// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {IWrappedfCashFactory} from "../../interfaces/notional/IWrappedfCashFactory.sol";
import {IWrappedfCash} from "../../interfaces/notional/IWrappedfCash.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";
import {WETH9} from "../../interfaces/notional/WETH9.sol";
import {CToken} from "../../interfaces/notional/CToken.sol";
import {NotionalViews, Token} from "../../interfaces/notional/INotionalViews.sol";

contract NotionalBridgeContract is BridgeBase {
    IWrappedfCashFactory public constant FCASH_FACTORY =
        IWrappedfCashFactory(0x5D051DeB5db151C2172dCdCCD42e6A2953E27261);
    NotionalViews public constant NOTIONAL_VIEW = NotionalViews(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    address public constant ETH = address(0);
    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    /**
     * @notice Set the address of RollupProcessor.sol
     * @param _rollupProcessor Address of RollupProcessor.sol
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    receive() external payable {}

    /**
     *@notice apperove every token that ROLLUP_PROCESSOR might transfer away from the bridge contract
     */
    function preApproveForAll() external {
        uint16 maxCurrencyId = NOTIONAL_VIEW.getMaxCurrencyId();
        for (uint16 i = 1; i <= maxCurrencyId; ) {
            (Token memory assetToken, Token memory underlyingToken) = NOTIONAL_VIEW.getCurrency(i);
            _preApprove(IERC20(assetToken.tokenAddress));
            if (underlyingToken.tokenAddress != ETH) {
                _preApprove(IERC20(underlyingToken.tokenAddress));
            }
            unchecked {
                i++;
            }
        }
    }

    /**
     * @notice Convert function called by rollup processor, will enter or exit Notional lending position
     * @dev Will revert if the input asset or the output asset is invalid
     * @param _inputAssetA The input asset. For entering the market, we support underlying tokens (ETH, DAI, etc.)
     * and their corresponding ctokens. For exiting the market, we support every valid fcash token.
     * @param _outputAssetA The output asset. For entering the market, it should be a valid fcash token.
     For exiting the market, this should be either an underlying token or a ctoken.
     * @param _inputValue The amount of input token
     * @param _interactionNonce The interaction nonce of the call
     * @param _auxData For entering the market, this will be the market maturity. For exitng the market,
     * this will be 0.
     * @return outputValueA The amount of token (fcash token, ctoken, or underlying token) the bridge returned.
     */
    function convert(
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory,
        AztecTypes.AztecAsset memory _outputAssetA,
        AztecTypes.AztecAsset memory,
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
        if (_auxData != 0) {
            outputValueA = _enter(_inputAssetA, _outputAssetA, _inputValue);
        } else {
            outputValueA = _exit(_inputAssetA, _outputAssetA, _inputValue);
        }
        if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
            IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(_interactionNonce);
        }
    }

    /**
     * @notice Helper functon to compute the fcash amount
     * @dev If the token is a ctoken, then we need to convert the amount to its underlying in 8 decimals
     * @dev If the token is an underlying token, then we simply scale it to 8 decimals
     * @param _token is the address of input asset token
     * @param _underlyingToken is the address of the underlying asset of _token.
     * @param _amount is the amount of input asset token
     * If _token is an underlying token, then _underlyingToken == _token. If _token is a ctoken,
     * then _underlyingToken will be _token's underlying token.
     * @return underlyingAmount The amount of underlying token with 8 decimal
     */
    function computeUnderlyingAmount(
        address _token,
        address _underlyingToken,
        uint256 _amount
    ) public returns (uint88) {
        uint256 underlyingDecimals = (_underlyingToken != ETH) ? ERC20(_underlyingToken).decimals() : 18;
        if (_token != _underlyingToken) {
            uint256 exchangeRateCurrent = CToken(_token).exchangeRateCurrent();
            uint256 mantissa = 10 + underlyingDecimals;
            uint256 underlyingAmount = (_amount * exchangeRateCurrent) / (10**mantissa);
            return uint88(underlyingAmount);
        }
        if (underlyingDecimals >= 8) {
            return uint88(_amount / 10**(underlyingDecimals - 8));
        }
        return uint88(_amount * 10**(8 - underlyingDecimals));
    }

    /**
     * @notice Approve the fcash contract to use the input token and mint fcash token
     * @dev If the input token is ETH, we need to deposit it into WETH. If the token is a ctoken,
     * we need to call mintViaAsset. Otherwise, we just need to call mintViaUnderlying.
     * @dev Will revert if the wrapped fcash contract has not been deployed
     * @param _inputAsset The input token asset
     * @param _outputAsset The output token asset
     * @param _amount The amount of input token
     * @return outputAmount The amount of fcash token we actually receive
     */
    function _enter(
        AztecTypes.AztecAsset memory _inputAsset,
        AztecTypes.AztecAsset memory _outputAsset,
        uint256 _amount
    ) internal returns (uint256) {
        IWrappedfCash fcash = IWrappedfCash(_outputAsset.erc20Address);
        address inputToken;
        if (_inputAsset.assetType == AztecTypes.AztecAssetType.ETH) {
            WETH9(WETH).deposit{value: _amount}();
            inputToken = WETH;
        } else {
            inputToken = _inputAsset.erc20Address;
        }
        ERC20(inputToken).approve(address(fcash), _amount);
        (IERC20 underlyingToken, ) = fcash.getUnderlyingToken();
        if (address(underlyingToken) == ETH) {
            underlyingToken = IERC20(WETH);
        }
        uint88 fcashAmount = computeUnderlyingAmount(inputToken, address(underlyingToken), _amount);
        if (address(underlyingToken) != inputToken) {
            fcash.mintViaAsset(_amount, fcashAmount, address(this), 0);
        } else {
            fcash.mintViaUnderlying(_amount, fcashAmount, address(this), 0);
        }
        uint256 fcashBalance = ERC20(address(fcash)).balanceOf(address(this));
        ERC20(address(fcash)).approve(ROLLUP_PROCESSOR, fcashBalance);
        return fcashBalance;
    }

    /**
     * @notice Redeem fcash to the underlying token or the asset token
     * @dev Call redeemToAsset or redeemToUnderlying depends on the type of input token
     * @dev Since there might be a slippage, we need to compute the number
     * of received tokens manually
     * @param _inputAsset The input token asset
     * @param _outputAsset The output token asset
     * @param _amount The amount of the input asset
     * @return outputAmount The actual received amount of the output asset
     */
    function _exit(
        AztecTypes.AztecAsset memory _inputAsset,
        AztecTypes.AztecAsset memory _outputAsset,
        uint256 _amount
    ) internal returns (uint256) {
        bool isETH = _outputAsset.assetType == AztecTypes.AztecAssetType.ETH;
        address inputToken = _inputAsset.erc20Address;
        address outputToken = _outputAsset.erc20Address;
        (IERC20 cToken, , ) = IWrappedfCash(inputToken).getAssetToken();
        if (address(cToken) == outputToken) {
            IWrappedfCash(inputToken).redeemToAsset(_amount, address(this), 0);
        } else {
            IWrappedfCash(inputToken).redeemToUnderlying(_amount, address(this), 0);
        }
        uint256 currBalance = isETH
            ? IERC20(WETH).balanceOf(address(this))
            : IERC20(outputToken).balanceOf(address(this));
        if (outputToken == address(0)) {
            WETH9(WETH).withdraw(currBalance);
        }
        return currBalance;
    }

    /**
     * @notice approve ROLLUP_PROCESSOR to transfer _token
     * @param _token The address of the token we want to approve
     */
    function _preApprove(IERC20 _token) private {
        uint256 allowance = _token.allowance(address(this), ROLLUP_PROCESSOR);
        if (allowance < type(uint256).max) {
            _token.approve(ROLLUP_PROCESSOR, type(uint256).max - allowance);
        }
    }
}
