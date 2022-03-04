// SPDX-License-Identifier: GPLv2

pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDefiBridge} from "../../interfaces/IDefiBridge.sol";
import {AztecTypes} from "../../aztec/AztecTypes.sol";

interface ICurvePool {
    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);

    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external payable returns (uint256);
}

interface ILido {
    function submit(address _referral) external payable returns (uint256);
}

interface IWstETH {
    function wrap(uint256 _stETHAmount) external returns (uint256);
    function unwrap(uint256 _wstETHAmount) external returns (uint256);
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
}

interface IRollupProcessor {
    function receiveEthFromBridge(uint256 interactionNonce) external payable;
}

contract LidoBridge is IDefiBridge {
    using SafeERC20 for IERC20;

    address public immutable rollupProcessor;
    address public referral;

    ILido public lido = ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWstETH public wrappedStETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ICurvePool public curvePool = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    int128 private curveETHIndex = 0;
    int128 private curveStETHIndex = 1;

    constructor(address _rollupProcessor, address _referral) {
        rollupProcessor = _rollupProcessor;
        referral = _referral;
    }

    receive() external payable {}

    function convert(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 inputValue,
        uint256 interactionNonce,
        uint64
    )
        external
        payable
        override
        returns (
            uint256 outputValueA,
            uint256,
            bool isAsync
        )
    {
        require(msg.sender == rollupProcessor, "LidoBridge: Invalid Caller");

        bool isETHInput = inputAssetA.assetType == AztecTypes.AztecAssetType.ETH;
        bool isWstETHInput = inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 && inputAssetA.erc20Address == address(wrappedStETH);

        require(isETHInput || isWstETHInput, "LidoBridge: Invalid Input");

        isAsync = false;
        outputValueA = isETHInput ? wrapETH(inputValue, outputAssetA) : unwrapETH(inputValue, outputAssetA, interactionNonce);
    }

    /**
        Convert ETH -> wstETH
     */
    function wrapETH(uint256 inputValue, AztecTypes.AztecAsset calldata outputAsset) private returns (uint256 outputValue) {
        require(
            outputAsset.assetType == AztecTypes.AztecAssetType.ERC20 && outputAsset.erc20Address == address(wrappedStETH),
            "LidoBridge: Invalid Output Token"
        );

        // the minimum should be 1ETH:1STETH
        uint256 minOutput = inputValue;

        // Check with curve to see if we can get better exchange rate than 1 ETH : 1 STETH
        // Yes: use curve
        // No: deposit to Lido correct

        uint256 curveStETHBalance = curvePool.get_dy(curveETHIndex, curveStETHIndex, inputValue);

        if (curveStETHBalance > minOutput) {
            // exchange via curve since we can get a better rate
            curvePool.exchange{value: inputValue}(curveETHIndex, curveStETHIndex, inputValue, minOutput);
        } else {
            // deposit directly through lido since we cannot get better rate
            lido.submit{value: inputValue}(referral);
        }

        // since stETH is a rebase token, lets wrap it to wstETH before sending it back to the rollupProcessor
        uint256 outputStETHBalance = IERC20(address(lido)).balanceOf(address(this));

        IERC20(address(lido)).safeIncreaseAllowance(address(wrappedStETH), outputStETHBalance);
        outputValue = wrappedStETH.wrap(outputStETHBalance);

        // Give allowance for rollup processor to withdraw
        IERC20(address(wrappedStETH)).safeIncreaseAllowance(rollupProcessor, outputValue);
    }

    /**
        Convert wstETH to ETH
     */
    function unwrapETH(uint256 inputValue, AztecTypes.AztecAsset calldata outputAsset, uint256 interactionNonce) private returns (uint256 outputValue) {
        require(outputAsset.assetType == AztecTypes.AztecAssetType.ETH, "LidoBridge: Invalid Output Token");

        // Convert wstETH to stETH so we can exchange it on curve
        uint256 stETH = wrappedStETH.unwrap(inputValue);

        // Exchange stETH to ETH via curve
        IERC20(address(lido)).safeIncreaseAllowance(address(curvePool), stETH);
        outputValue = curvePool.exchange(curveStETHIndex, curveETHIndex, stETH, 0);

        // Send ETH to rollup processor
        IRollupProcessor(rollupProcessor).receiveEthFromBridge{value: outputValue}(interactionNonce);
    }

  function finalise(
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata,
    uint256,
    uint64
  ) external payable override returns (uint256, uint256, bool) {
    require(false);
  }
}
