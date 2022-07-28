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
    mapping(address => mapping(address => bool)) public preapproved;

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        uint16 maxCurrencyId = NOTIONAL_VIEW.getMaxCurrencyId();
        for (uint16 i = 1; i <= maxCurrencyId; ) {
            (Token memory assetToken, Token memory underlyingToken) = NOTIONAL_VIEW.getCurrency(i);
            ERC20(assetToken.tokenAddress).approve(_rollupProcessor, type(uint256).max);
            preapproved[assetToken.tokenAddress][_rollupProcessor] = true;
            if (underlyingToken.tokenAddress != ETH) {
                ERC20(underlyingToken.tokenAddress).approve(_rollupProcessor, type(uint256).max);
                preapproved[underlyingToken.tokenAddress][_rollupProcessor] = true;
            }
            unchecked {
                i++;
            }
        }
    }

    receive() external payable {}

    /**
     * @notice Convert function called by rollup processor, will enter or exit Notional lending position
     * @dev Will revert if the input asset or the output asset is invalid
     * @param _inputAssetA The input asset. For entering the market, we support ETH, USDC, DAI, WBTC
     * and their corresponding ctokens. For exiting the market, we support every valid fcash token.
     * @param _outputAssetA The output asset. For entering the market, it should be a valid fcash token.
     For exiting the market, this should be one of ETH, USDC, DAI, WBTC, and their corresponding ctokesn
     * @param _inputValue The amount of input token
     * @param _interactionNonce The interaction nonce of the call
     * @param _auxData For entering the market, this will be the market maturity. For exitng the market,
     * this will be 0.
     * @return outputValueA The amount of token (fcash token or ctoken or underlying token) the bridge reveived.
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
        uint40 maturity = uint40(_auxData);
        if (maturity != 0) {
            uint16 currencyId = IWrappedfCash(_outputAssetA.erc20Address).getCurrencyId();
            outputValueA = _enter(
                _inputAssetA.erc20Address,
                _outputAssetA.erc20Address,
                currencyId,
                _inputValue,
                maturity
            );
        } else {
            outputValueA = _exit(_inputAssetA.erc20Address, _outputAssetA.erc20Address, _inputValue);
        }
        if (
            _outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 &&
            !preapproved[_outputAssetA.erc20Address][ROLLUP_PROCESSOR]
        ) {
            // if it's not preapproved, we need to approve it
            ERC20(_outputAssetA.erc20Address).approve(ROLLUP_PROCESSOR, type(uint256).max);
            preapproved[_outputAssetA.erc20Address][ROLLUP_PROCESSOR] = true;
        } else if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
            IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(_interactionNonce);
        }
    }

    /**
     * @notice Helper functon to compute the fcash amount
     * @dev If the token is a ctoken, then we need to convert the amount to its underlying in 8 decimals
     * @dev If the token is an underlying token, then we simply scale it to 8 decimals
     * @param _token is the address of input asset token
     * @param _amount is the amount of input asset token
     * @return underlyingAmount The amount of underlying token with 8 decimal
     */
    function computeUnderlyingAmount(
        address _token,
        address _underlyingToken,
        uint256 _amount
    ) public returns (uint88) {
        uint256 underlyingDecimals = ERC20(_underlyingToken).decimals();
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
     * @param _inputToken The address of the input asset
     * @param _outputToken The address of the output asset
     * @param _currencyId The predefined Notional currency id defined in constructor
     * @param _amount The amount of input token
     * @param _maturity The maturity of the market we want to enter
     * @return outputAmount The amount of fcash token we actually receive
     */
    function _enter(
        address _inputToken,
        address _outputToken,
        uint16 _currencyId,
        uint256 _amount,
        uint40 _maturity
    ) internal returns (uint256) {
        IWrappedfCash fcash = IWrappedfCash(FCASH_FACTORY.computeAddress(_currencyId, _maturity));
        if (address(fcash) != _outputToken) {
            revert ErrorLib.InvalidOutputA();
        }
        if (_inputToken == address(0)) {
            WETH9(WETH).deposit{value: _amount}();
            _inputToken = WETH;
        }
        if (!preapproved[_inputToken][address(fcash)]) {
            ERC20(_inputToken).approve(address(fcash), type(uint256).max);
            preapproved[_inputToken][address(fcash)] = true;
        }
        if (fcash.getCurrencyId() != _currencyId) {
            revert("fcash has not been deployed");
        }
        (IERC20 underlyingToken, ) = fcash.getUnderlyingToken();
        if (address(underlyingToken) == ETH) {
            underlyingToken = IERC20(WETH);
        }
        uint88 fcashAmount = computeUnderlyingAmount(_inputToken, address(underlyingToken), _amount);
        if (address(underlyingToken) != _inputToken) {
            fcash.mintViaAsset(_amount, fcashAmount, address(this), 0);
        } else {
            fcash.mintViaUnderlying(_amount, fcashAmount, address(this), 0);
        }
        return ERC20(address(fcash)).balanceOf(address(this));
    }

    /**
     * @notice Redeem fcash to the underlying token or the asset token
     * @dev Call redeemToAsset or redeemToUnderlying depends on the type of input token
     * @dev Since there might be a slippage, we need to compute the number
     * of received tokens manually
     * @param _inputToken The address of the input asset
     * @param _outputToken The address of the output asset
     * @param _amount The amount of the input asset
     * @return outputAmount The actual received amount of the output asset
     */
    function _exit(
        address _inputToken,
        address _outputToken,
        uint256 _amount
    ) internal returns (uint256) {
        bool isETH = address(_outputToken) == address(0);
        uint256 prevBalance = isETH
            ? IERC20(WETH).balanceOf(address(this))
            : IERC20(_outputToken).balanceOf(address(this));
        (IERC20 cToken, , ) = IWrappedfCash(_inputToken).getAssetToken();
        if (address(cToken) == _outputToken) {
            IWrappedfCash(_inputToken).redeemToAsset(_amount, address(this), 0);
        } else {
            IWrappedfCash(_inputToken).redeemToUnderlying(_amount, address(this), 0);
        }
        uint256 currBalance = isETH
            ? IERC20(WETH).balanceOf(address(this))
            : IERC20(_outputToken).balanceOf(address(this));
        if (_outputToken == address(0)) {
            WETH9(WETH).withdraw(currBalance);
        }
        return currBalance - prevBalance;
    }
}
