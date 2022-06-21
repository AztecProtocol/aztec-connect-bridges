// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ICurvePool} from "../../interfaces/curve/ICurvePool.sol";
import {ILido} from "../../interfaces/lido/ILido.sol";
import {IWstETH} from "../../interfaces/lido/IWstETH.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";

import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CurveStEthBridge is BridgeBase {
    using SafeERC20 for ILido;
    using SafeERC20 for IWstETH;

    error InvalidConfiguration();
    error InvalidWrapReturnValue();
    error InvalidUnwrapReturnValue();

    ILido public constant LIDO = ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWstETH public constant WRAPPED_STETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ICurvePool public constant CURVE_POOL = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    int128 private constant CURVE_ETH_INDEX = 0;
    int128 private constant CURVE_STETH_INDEX = 1;

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        if (CURVE_POOL.coins(uint256(uint128(CURVE_STETH_INDEX))) != address(LIDO)) {
            revert InvalidConfiguration();
        }

        // As the contract is not supposed to hold any funds, we can pre-approve
        LIDO.safeIncreaseAllowance(address(WRAPPED_STETH), type(uint256).max);
        LIDO.safeIncreaseAllowance(address(CURVE_POOL), type(uint256).max);
        WRAPPED_STETH.safeIncreaseAllowance(ROLLUP_PROCESSOR, type(uint256).max);
    }

    receive() external payable {}

    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256,
            bool isAsync
        )
    {
        bool isETHInput = _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH;
        bool isWstETHInput = _inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 &&
            _inputAssetA.erc20Address == address(WRAPPED_STETH);

        if (!(isETHInput || isWstETHInput)) {
            revert ErrorLib.InvalidInputA();
        }

        isAsync = false;
        outputValueA = isETHInput
            ? _wrapETH(_inputValue, _outputAssetA)
            : _unwrapETH(_inputValue, _outputAssetA, _interactionNonce);
    }

    /**
        Convert ETH -> wstETH
     */
    function _wrapETH(uint256 _inputValue, AztecTypes.AztecAsset calldata _outputAsset)
        private
        returns (uint256 outputValue)
    {
        if (
            _outputAsset.assetType != AztecTypes.AztecAssetType.ERC20 ||
            _outputAsset.erc20Address != address(WRAPPED_STETH)
        ) {
            revert ErrorLib.InvalidOutputA();
        }

        // Swap eth -> stEth on curve
        uint256 dy = CURVE_POOL.exchange{value: _inputValue}(CURVE_ETH_INDEX, CURVE_STETH_INDEX, _inputValue, 0);

        // wrap stEth
        outputValue = WRAPPED_STETH.wrap(dy);
    }

    /**
        Convert wstETH to ETH
     */
    function _unwrapETH(
        uint256 _inputValue,
        AztecTypes.AztecAsset calldata _outputAsset,
        uint256 _interactionNonce
    ) private returns (uint256 outputValue) {
        if (_outputAsset.assetType != AztecTypes.AztecAssetType.ETH) {
            revert ErrorLib.InvalidOutputA();
        }

        // Convert wstETH to stETH so we can exchange it on curve
        uint256 stETH = WRAPPED_STETH.unwrap(_inputValue);

        // Exchange stETH to ETH via curve
        uint256 dy = CURVE_POOL.exchange(CURVE_STETH_INDEX, CURVE_ETH_INDEX, stETH, 0);

        outputValue = address(this).balance;
        if (outputValue < dy) {
            revert InvalidUnwrapReturnValue();
        }

        // Send ETH to rollup processor
        IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValue}(_interactionNonce);
    }
}
