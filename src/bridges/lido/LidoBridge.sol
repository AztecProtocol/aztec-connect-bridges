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

contract LidoBridge is BridgeBase {
    using SafeERC20 for ILido;
    using SafeERC20 for IWstETH;

    error InvalidConfiguration();
    error InvalidWrapReturnValue();
    error InvalidUnwrapReturnValue();

    address public immutable REFERRAL;

    ILido public constant LIDO = ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWstETH public constant WRAPPED_STETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ICurvePool public constant CURVE_POOL = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    int128 private constant CURVE_ETH_INDEX = 0;
    int128 private constant CURVE_STETH_INDEX = 1;

    // The amount of dust to leave in the contract
    uint256 private constant DUST = 1;

    constructor(address _rollupProcessor, address _referral) BridgeBase(_rollupProcessor) {
        if (CURVE_POOL.coins(uint256(uint128(CURVE_STETH_INDEX))) != address(LIDO)) {
            revert InvalidConfiguration();
        }

        REFERRAL = _referral;

        // As the contract is not supposed to hold any funds, we can pre-approve
        LIDO.safeIncreaseAllowance(address(WRAPPED_STETH), type(uint256).max);
        LIDO.safeIncreaseAllowance(address(CURVE_POOL), type(uint256).max);
        WRAPPED_STETH.safeIncreaseAllowance(ROLLUP_PROCESSOR, type(uint256).max);
    }

    receive() external payable {}

    function convert(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 inputValue,
        uint256 interactionNonce,
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
        bool isETHInput = inputAssetA.assetType == AztecTypes.AztecAssetType.ETH;
        bool isWstETHInput = inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 &&
            inputAssetA.erc20Address == address(WRAPPED_STETH);

        if (!(isETHInput || isWstETHInput)) {
            revert ErrorLib.InvalidInputA();
        }

        isAsync = false;
        outputValueA = isETHInput
            ? wrapETH(inputValue, outputAssetA)
            : unwrapETH(inputValue, outputAssetA, interactionNonce);
    }

    /**
        Convert ETH -> wstETH
     */
    function wrapETH(uint256 inputValue, AztecTypes.AztecAsset calldata outputAsset)
        private
        returns (uint256 outputValue)
    {
        if (
            outputAsset.assetType != AztecTypes.AztecAssetType.ERC20 ||
            outputAsset.erc20Address != address(WRAPPED_STETH)
        ) {
            revert ErrorLib.InvalidOutputA();
        }

        // deposit into lido (return value is shares NOT stETH)
        LIDO.submit{value: inputValue}(REFERRAL);

        // Leave `DUST` in the stEth balance to save gas on future runs
        uint256 outputStETHBalance = LIDO.balanceOf(address(this)) - DUST;

        // Lido balance can be <=2 wei off, 1 from the submit where our shares is computed rounding down,
        // and then again when the balance is computed from the shares, rounding down again.
        if (outputStETHBalance + 2 + DUST < inputValue) {
            revert InvalidWrapReturnValue();
        }

        // since stETH is a rebase token, lets wrap it to wstETH before sending it back to the rollupProcessor.
        // Again, leave `DUST` in the wstEth balance to save gas on future runs
        outputValue = WRAPPED_STETH.wrap(outputStETHBalance) - DUST;
    }

    /**
        Convert wstETH to ETH
     */
    function unwrapETH(
        uint256 inputValue,
        AztecTypes.AztecAsset calldata outputAsset,
        uint256 interactionNonce
    ) private returns (uint256 outputValue) {
        if (outputAsset.assetType != AztecTypes.AztecAssetType.ETH) {
            revert ErrorLib.InvalidOutputA();
        }

        // Convert wstETH to stETH so we can exchange it on curve
        uint256 stETH = WRAPPED_STETH.unwrap(inputValue);

        // Exchange stETH to ETH via curve
        uint256 dy = CURVE_POOL.exchange(CURVE_STETH_INDEX, CURVE_ETH_INDEX, stETH, 0);

        outputValue = address(this).balance;
        if (outputValue < dy) {
            revert InvalidUnwrapReturnValue();
        }

        // Send ETH to rollup processor
        IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValue}(interactionNonce);
    }
}
