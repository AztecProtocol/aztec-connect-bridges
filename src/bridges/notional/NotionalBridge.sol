// SPDX-License-Identifier: GPL-2.0-only
pragma solidity >=0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {IWrappedfCashFactory} from "./interfaces/notional/IWrappedfCashFactory.sol";
import {IWrappedfCash} from "./interfaces/notional/IWrappedfCash.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";
import {WETH9} from "./interfaces/WETH9.sol";
import {CToken} from "./interfaces/CToken.sol";

contract NotionalBridgeContract is BridgeBase {
    IWrappedfCashFactory public fcashFactory;
    address public constant ETH = address(0);
    address public constant CETH = address(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
    address public constant DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address public constant CDAI = address(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public constant CUSDC = address(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
    address public constant WBTC = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    address public constant CWBTC = address(0xC11b1268C1A384e55C48c2391d8d480264A3A7F4);
    mapping(address => uint16) public currencyIds;
    mapping(address => bool) public ctokens;
    mapping(address => address) public underlyingAddrMap;

    constructor(address _rollupProcessor, address _fcashFactory) BridgeBase(_rollupProcessor) {
        fcashFactory = IWrappedfCashFactory(_fcashFactory);
        currencyIds[ETH] = 1;
        currencyIds[CETH] = 1;
        currencyIds[WETH] = 1;
        currencyIds[DAI] = 2;
        currencyIds[CDAI] = 2;
        currencyIds[USDC] = 3;
        currencyIds[CUSDC] = 3;
        currencyIds[WBTC] = 4;
        currencyIds[CWBTC] = 4;
        underlyingAddrMap[CETH] = WETH;
        underlyingAddrMap[CDAI] = DAI;
        underlyingAddrMap[CUSDC] = USDC;
        underlyingAddrMap[CWBTC] = WBTC;
        ctokens[CETH] = true;
        ctokens[CDAI] = true;
        ctokens[CUSDC] = true;
        ctokens[CWBTC] = true;
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
        _validateInput(maturity, _inputAssetA.erc20Address, _outputAssetA.erc20Address);
        uint16 currencyId = currencyIds[_inputAssetA.erc20Address];
        if (currencyId != 0) {
            if (_inputAssetA.erc20Address == address(0) || _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                if (msg.value != _inputValue) {
                    revert("not enough ether");
                }
            }
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
        if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
            ERC20(_outputAssetA.erc20Address).approve(ROLLUP_PROCESSOR, outputValueA);
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
     */
    function computeUnderlyingAmount(address _token, uint256 _amount) public returns (uint88) {
        bool isCtoken = ctokens[_token];
        address underlyingToken = underlyingAddrMap[_token];
        if (isCtoken) {
            uint256 underlyingDecimals = ERC20(underlyingToken).decimals();
            uint256 exchangeRateCurrent = CToken(_token).exchangeRateCurrent();
            uint256 mantissa = 10 + underlyingDecimals;
            uint256 underlyingAmount = (_amount * exchangeRateCurrent) / (10**mantissa);
            return uint88(underlyingAmount);
        }
        uint256 decimal = ERC20(_token).decimals();
        if (decimal >= 8) {
            return uint88(_amount / 10**(decimal - 8));
        }
        return uint88(_amount * 10**(8 - decimal));
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
     */
    function _enter(
        address _inputToken,
        address _outputToken,
        uint16 _currencyId,
        uint256 _amount,
        uint40 _maturity
    ) internal returns (uint256) {
        IWrappedfCash fcash = IWrappedfCash(fcashFactory.computeAddress(_currencyId, _maturity));
        if (address(fcash) != _outputToken) {
            revert ErrorLib.InvalidOutputA();
        }
        if (_inputToken == address(0)) {
            WETH9(WETH).deposit{value: _amount}();
            _inputToken = WETH;
        }
        ERC20(_inputToken).approve(address(fcash), _amount);
        if (fcash.getCurrencyId() != _currencyId) {
            revert("fcash has not been deployed");
        }
        uint88 fcashAmount = computeUnderlyingAmount(_inputToken, _amount);
        if (ctokens[_inputToken]) {
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
        if (ctokens[_outputToken]) {
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

    /**
     * @notice validate the input asset and output asset
     * @dev For entering the market, we make sure the user passes in the supported input asset list
     * For exiting the market, we make sure the user passes in the supported output asset list
     * @param _maturity The maturity of the market we want to enter. It also indicates
     * whether this is for entering the market or exiting the market
     * @param _inputAsset The address of the input asset
     * @param _outputAsset The address of the output asset
     */
    function _validateInput(
        uint40 _maturity,
        address _inputAsset,
        address _outputAsset
    ) internal view {
        uint16 currencyId = _maturity == 0 ? currencyIds[_outputAsset] : currencyIds[_inputAsset];
        if (currencyId == 0) {
            if (_maturity == 0) {
                revert ErrorLib.InvalidOutputA();
            }
            revert ErrorLib.InvalidInputA();
        }
    }
}
