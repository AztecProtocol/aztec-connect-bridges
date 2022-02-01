// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IDefiBridge } from "../../../interfaces/IDefiBridge.sol";
import { IWETH } from "../../../interfaces/IWETH.sol";
import { ICurveProvider } from "../../../interfaces/ICurveProvider.sol";
import { ICurveExchange } from "../../../interfaces/ICurveExchange.sol";
import { IRollupProcessor } from "../../../interfaces/IRollupProcessor.sol";

import { AztecTypes } from "../../../AztecTypes.sol";

contract CurveSwapBridge is IDefiBridge {
  using SafeERC20 for IERC20;

  uint256 private constant CURVE_SWAPS_ADDRESS_INDEX = 2;

  IRollupProcessor public immutable rollupProcessor;
  IWETH public immutable weth;
  ICurveProvider public curveAddressProvider;

  constructor(
    address _rollupProcessor,
    address _addressProvider,
    address _weth
  ) {
    rollupProcessor = IRollupProcessor(_rollupProcessor);
    curveAddressProvider = ICurveProvider(_addressProvider);
    weth = IWETH(_weth);
  }

  // solhint-disable-next-line no-empty-blocks
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
      uint256 outputValueB,
      bool isAsync
    )
  {
    require(msg.sender == address(rollupProcessor), "INVALID_CALLER");
    require(
      inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 ||
        inputAssetA.assetType == AztecTypes.AztecAssetType.ETH,
      "INVALID_INPUT_ASSET_TYPE"
    );
    require(
      inputAssetA.assetType != AztecTypes.AztecAssetType.ETH ||
        msg.value == inputValue,
      "INVALID_ETH_VALUE"
    );
    require(
      outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 ||
        outputAssetA.assetType == AztecTypes.AztecAssetType.ETH,
      "INVALID_OUTPUT_ASSET_TYPE"
    );

    outputValueA = _convert(inputAssetA, outputAssetA, inputValue, interactionNonce);
    outputValueB = 0;
    isAsync = false;
  }

  function _convert(
    AztecTypes.AztecAsset calldata input,
    AztecTypes.AztecAsset calldata output,
    uint256 inputValue,
    uint256 interactionNonce
  ) internal returns (uint256) {
    address inputAddr;

    if (input.assetType == AztecTypes.AztecAssetType.ETH) {
      weth.deposit{ value: msg.value }();
      inputAddr = address(weth);
    } else {
      inputAddr = input.erc20Address;
    }

    address outputAddr;
    if (output.assetType == AztecTypes.AztecAssetType.ETH) {
      outputAddr = address(weth);
    } else {
      outputAddr = output.erc20Address;
    }

    ICurveExchange curveExchange = ICurveExchange(
      curveAddressProvider.get_address(CURVE_SWAPS_ADDRESS_INDEX)
    );
    IERC20(inputAddr).safeIncreaseAllowance(address(curveExchange), inputValue);

    address pool;
    uint256 rate;
    (pool, rate) = curveExchange.get_best_rate(
      inputAddr,
      outputAddr,
      inputValue
    );

    uint256 resultAmount = curveExchange.exchange(
      pool,
      inputAddr,
      outputAddr,
      inputValue,
      0 // TODO - adjust minimum for slippage
    );

    if (output.assetType == AztecTypes.AztecAssetType.ETH) {
      weth.withdraw(resultAmount);
      rollupProcessor.receiveEthFromBridge{value: resultAmount}(interactionNonce);
    } else if (output.assetType == AztecTypes.AztecAssetType.ERC20) {
      IERC20(outputAddr).safeIncreaseAllowance(address(rollupProcessor), resultAmount);
    }

    return resultAmount;
  }

  function canFinalise(uint256) external pure override returns (bool) {
    return false;
  }

  function finalise(
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata,
    uint256,
    uint64
  ) external payable override returns (uint256, uint256) {
    require(false, "FINALISE_UNSUPPORTED");
    return (0, 0);
  }
}
