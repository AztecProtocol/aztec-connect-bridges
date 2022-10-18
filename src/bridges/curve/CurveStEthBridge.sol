// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {ICurvePool} from "../../interfaces/curve/ICurvePool.sol";
import {ILido} from "../../interfaces/lido/ILido.sol";
import {IWstETH} from "../../interfaces/lido/IWstETH.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";

import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @notice A DeFiBridge for trading between Eth and wstEth using curve and the stEth wrapper.
 * @dev Synchronous and stateless bridge that will hold no funds beyond dust for gas-savings.
 * @author Aztec Team
 */
contract CurveStEthBridge is BridgeBase {
    using SafeERC20 for ILido;
    using SafeERC20 for IWstETH;

    error InvalidConfiguration();
    error InvalidUnwrapReturnValue();

    ILido public constant LIDO = ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWstETH public constant WRAPPED_STETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ICurvePool public constant CURVE_POOL = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    uint256 public constant PRECISION = 1e18;

    // Indexes of the assets in the curve pool
    int128 private constant CURVE_ETH_INDEX = 0;
    int128 private constant CURVE_STETH_INDEX = 1;

    /**
     * @notice Sets the address of the RollupProcessor and pre-approve tokens
     * @dev As the contract will not be holding state nor tokens, it can be approved safely.
     * @param _rollupProcessor The address of the RollupProcessor to use
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        if (CURVE_POOL.coins(uint256(uint128(CURVE_STETH_INDEX))) != address(LIDO)) {
            revert InvalidConfiguration();
        }

        LIDO.safeIncreaseAllowance(address(WRAPPED_STETH), type(uint256).max);
        LIDO.safeIncreaseAllowance(address(CURVE_POOL), type(uint256).max);
        WRAPPED_STETH.safeIncreaseAllowance(ROLLUP_PROCESSOR, type(uint256).max);
    }

    // Empty receive function for the contract to be able to receive Eth
    receive() external payable {}

    /**
     * @notice Swaps between the eth<->wstEth tokens through the curve eth/stEth pool and wrapping stEth
     * @param _inputAssetA The inputAsset (eth or wstEth)
     * @param _outputAssetA The output asset (eth or wstEth) opposite `_inputAssetB`
     * @param _totalInputValue The amount of token deposited
     * @param _interactionNonce The nonce of the DeFi interaction, used when swapping wstEth -> eth
     * @param _auxData For eth->wstEth, the minimum acceptable amount of stEth per 1 eth, for wstEth->eth, the minimum
     *                 acceptable amount of eth per 1 wstEth.
     * @return outputValueA The amount of `_outputAssetA` that the RollupProcessor should pull
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
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256,
            bool
        )
    {
        bool isETHInput = _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH;
        bool isWstETHInput = _inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 &&
            _inputAssetA.erc20Address == address(WRAPPED_STETH);

        if (!(isETHInput || isWstETHInput)) {
            revert ErrorLib.InvalidInputA();
        }

        outputValueA = isETHInput
            ? _wrapETH(_totalInputValue, _outputAssetA, _auxData)
            : _unwrapETH(_totalInputValue, _outputAssetA, _auxData, _interactionNonce);
    }

    /**
     * @notice Swaps eth to stEth through curve and wrap the stEth into wstEth
     * @dev Reverts if `_outputAsset` is not wstEth
     * @param _totalInputValue The amount of token that is deposited
     * @param _outputAsset The asset that the DeFi interaction specify as output, must be wstEth
     * @param _minStEthPerEth Smallest acceptable amount of steth for each eth
     * @return outputValue The amount of wstEth received from the interaction
     */
    function _wrapETH(
        uint256 _totalInputValue,
        AztecTypes.AztecAsset calldata _outputAsset,
        uint256 _minStEthPerEth
    ) private returns (uint256 outputValue) {
        if (
            _outputAsset.assetType != AztecTypes.AztecAssetType.ERC20 ||
            _outputAsset.erc20Address != address(WRAPPED_STETH)
        ) {
            revert ErrorLib.InvalidOutputA();
        }

        uint256 minDy = (_totalInputValue * _minStEthPerEth) / PRECISION;

        // Swap eth -> stEth on curve
        uint256 dy = CURVE_POOL.exchange{value: _totalInputValue}(
            CURVE_ETH_INDEX,
            CURVE_STETH_INDEX,
            _totalInputValue,
            minDy
        );

        // wrap stEth
        outputValue = WRAPPED_STETH.wrap(dy);
    }

    /**
     * @notice Unwraps wstEth and swap stEth to eth through curve
     * @dev Reverts if `_outputAsset` is not eth
     * @param _totalInputValue The amount of token that is deposited
     * @param _outputAsset The asset that the DeFi interaction specify as output, must be eth
     * @param _minEthPerStEth Smallest acceptable amount of eth for each steth
     * @return outputValue The amount of eth received from the interaction
     */
    function _unwrapETH(
        uint256 _totalInputValue,
        AztecTypes.AztecAsset calldata _outputAsset,
        uint256 _minEthPerStEth,
        uint256 _interactionNonce
    ) private returns (uint256 outputValue) {
        if (_outputAsset.assetType != AztecTypes.AztecAssetType.ETH) {
            revert ErrorLib.InvalidOutputA();
        }

        // Convert wstETH to stETH so we can exchange it on curve
        uint256 stETH = WRAPPED_STETH.unwrap(_totalInputValue);

        uint256 minDy = (stETH * _minEthPerStEth) / PRECISION;
        // Exchange stETH to ETH via curve
        uint256 dy = CURVE_POOL.exchange(CURVE_STETH_INDEX, CURVE_ETH_INDEX, stETH, minDy);

        outputValue = address(this).balance;
        if (outputValue < dy) {
            revert InvalidUnwrapReturnValue();
        }

        // Send ETH to rollup processor
        IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValue}(_interactionNonce);
    }
}
