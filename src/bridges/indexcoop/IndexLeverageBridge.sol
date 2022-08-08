// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";
import {ISetToken} from "../../interfaces/set/ISetToken.sol";
import {IExchangeIssuanceLeveraged} from "../../interfaces/set/IExchangeIssuanceLeveraged.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title IndexCoop Leveraged Tokens Bridge
 * @notice A smart contract responsible for buying and selling icETH with ETH either through selling/buying from
 * a DEX or by issuing/redeeming icEth set tokens.
 */
contract IndexLeverageBridge is BridgeBase {
    using SafeERC20 for IERC20;

    address public constant EXCHANGE_ISSUANCE = 0xB7cc88A13586D862B97a677990de14A122b74598;
    address public constant CURVE = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant ICETH = 0x7C07F7aBe10CE8e33DC6C5aD68FE033085256A84;

    uint256 public constant PRECISION = 1e18;
    uint256 public constant DUST = 1;

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        // Tokens can be pre approved since the bridge should not hold any tokens.
        IERC20(ICETH).safeIncreaseAllowance(address(EXCHANGE_ISSUANCE), type(uint256).max);
        IERC20(ICETH).safeIncreaseAllowance(ROLLUP_PROCESSOR, type(uint256).max);
    }

    receive() external payable {}

    /**
     * @notice Function that swaps between icETH and ETH.
     * @dev The flow of this functions is based on the type of input and output assets.
     *
     * @param _inputAssetA - ETH to buy/issue icETH, icETH to sell/redeem icETH.
     * @param _outputAssetA - icETH to buy/issue icETH, ETH to sell/redeem icETH.
     * @param _outputAssetB - ETH to buy/issue icETH, empty to sell/redeem icETH.
     * @param _totalInputValue - Total amount of ETH/icETH to be swapped for icETH/ETH
     * @param _interactionNonce - Globally unique identifier for this bridge call
     * @param _auxData - Encodes flowSelector and maxSlip. See notes on the decodeAuxData
     * function for encoding details.
     * @return outputValueA - Amount of icETH received when buying/issuing, Amount of ETH
     * received when selling/redeeming.
     * @return outputValueB - Amount of ETH returned when issuing icETH. A portion of ETH
     * is always returned when issuing icETH since the issuing function in ExchangeIssuance
     * requires an exact output amount rather than input.
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata _outputAssetB,
        uint256 _totalInputValue,
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
            uint256 outputValueB,
            bool
        )
    {
        /**
            Inputs that are too small will result in a loss of precision
            in flashloan calculations. In getAmountBasedOnRedeem() debtOWned
            and colInEth will lose precision. Dito in ExchangeIssuance.
        */
        if (_totalInputValue < 1e18) revert ErrorLib.InvalidInputAmount();

        uint256 amountOut = (_totalInputValue * _auxData) / PRECISION;

        if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH &&
            _outputAssetA.erc20Address == ICETH &&
            _outputAssetB.assetType == AztecTypes.AztecAssetType.ETH
        ) {
            // Mint leveraged token

            uint24[] memory fee;
            address[] memory pathToSt = new address[](2);
            pathToSt[0] = ETH;
            pathToSt[1] = STETH;

            IExchangeIssuanceLeveraged.SwapData memory issueData = IExchangeIssuanceLeveraged.SwapData(
                pathToSt,
                fee,
                CURVE,
                IExchangeIssuanceLeveraged.Exchange.Curve
            );

            IExchangeIssuanceLeveraged(EXCHANGE_ISSUANCE).issueExactSetFromETH{value: _totalInputValue}(
                ISetToken(ICETH),
                amountOut,
                issueData,
                issueData
            );

            outputValueA = ISetToken(ICETH).balanceOf(address(this)) - DUST;
            outputValueB = address(this).balance;
        } else if (
            _inputAssetA.erc20Address == ICETH &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.ETH &&
            _outputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED
        ) {
            // Redeem underlying

            // Creating a SwapData structure used to specify a path in a DEX in the ExchangeIssuance contract
            uint24[] memory fee;
            address[] memory pathToEth = new address[](2);
            pathToEth[0] = STETH;
            pathToEth[1] = ETH;

            IExchangeIssuanceLeveraged.SwapData memory redeemData = IExchangeIssuanceLeveraged.SwapData(
                pathToEth,
                fee,
                CURVE,
                IExchangeIssuanceLeveraged.Exchange.Curve
            );

            // Redeem icETH for eth
            IExchangeIssuanceLeveraged(EXCHANGE_ISSUANCE).redeemExactSetForETH(
                ISetToken(ICETH),
                _totalInputValue,
                amountOut,
                redeemData,
                redeemData
            );

            outputValueA = address(this).balance;
            IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(_interactionNonce);
        } else {
            revert ErrorLib.InvalidInput();
        }
    }
}
