// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <0.8.11;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
//import { IV3SwapRouter as ISwapRouter } from "@uniswap/swap-router-contracts/contracts/interfaces/IV3SwapRouter.sol";
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import { IDefiBridge } from "./interfaces/IDefiBridge.sol";
import { AztecTypes } from "./Types.sol";

import 'hardhat/console.sol';

contract DefiBridgeProxy {
  using SafeMath for uint256;

  bytes4 private constant BALANCE_OF_SELECTOR = 0x70a08231; // bytes4(keccak256('balanceOf(address)'));
  bytes4 private constant TRANSFER_SELECTOR = 0xa9059cbb; // bytes4(keccak256('transfer(address,uint256)'));
  bytes4 private constant DEPOSIT_SELECTOR = 0xb6b55f25; // bytes4(keccak256('deposit(uint256)'));
  bytes4 private constant WITHDRAW_SELECTOR = 0x2e1a7d4d; // bytes4(keccak256('withdraw(uint256)'));

  event AztecBridgeInteraction(
    address indexed bridgeAddress,
    uint256 outputValueA,
    uint256 outputValueB,
    bool isAsync
  );

  receive() external payable {}

  function getBalance(address assetAddress)
    internal
    view
    returns (uint256 result)
  {
    assembly {
      if iszero(assetAddress) {
        // This is ETH.
        result := balance(address())
      }
      if assetAddress {
        // Is this a token.
        let ptr := mload(0x40)
        mstore(ptr, BALANCE_OF_SELECTOR)
        mstore(add(ptr, 0x4), address())
        if iszero(staticcall(gas(), assetAddress, ptr, 0x24, ptr, 0x20)) {
          // Call failed.
          revert(0x00, 0x00)
        }
        result := mload(ptr)
      }
    }
  }

  function transferTokens(
    address assetAddress,
    address to,
    uint256 amount
  ) internal {
    assembly {
      let ptr := mload(0x40)
      mstore(ptr, TRANSFER_SELECTOR)
      mstore(add(ptr, 0x4), to)
      mstore(add(ptr, 0x24), amount)
      // is this correct or should we forward the correct amount
      if iszero(call(gas(), assetAddress, 0, ptr, 0x44, ptr, 0)) {
        // Call failed.
        revert(0x00, 0x00)
      }
    }
  }

  function convert(
    address bridgeAddress,
    AztecTypes.AztecAsset calldata inputAssetA,
    AztecTypes.AztecAsset calldata inputAssetB,
    AztecTypes.AztecAsset calldata outputAssetA,
    AztecTypes.AztecAsset calldata outputAssetB,
    uint256 totalInputValue,
    uint256 interactionNonce,
    uint256 auxInputData // (auxData)
  )
    external
    returns (
      uint256 outputValueA,
      uint256 outputValueB,
      bool isAsync
    )
  {
    if (inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
      // Transfer totalInputValue to the bridge contract if erc20. ETH is sent on call to convert.
      transferTokens(inputAssetA.erc20Address, bridgeAddress, totalInputValue);
    }

    if (inputAssetB.assetType == AztecTypes.AztecAssetType.ERC20) {
      // Transfer totalInputValue to the bridge contract if erc20. ETH is sent on call to convert.
      transferTokens(inputAssetB.erc20Address, bridgeAddress, totalInputValue);
    }

    uint256 tempValueA;
    uint256 tempValueB;

    if (outputAssetA.assetType != AztecTypes.AztecAssetType.VIRTUAL) {
      tempValueA = getBalance(outputAssetA.erc20Address);
    }

    if (outputAssetB.assetType != AztecTypes.AztecAssetType.VIRTUAL) {
      tempValueB = getBalance(outputAssetB.erc20Address);
    }

    // Call bridge.convert(), which will return output values for the two output assets.
    // If input is ETH, send it along with call to convert.
    IDefiBridge bridgeContract = IDefiBridge(bridgeAddress);
    (outputValueA, outputValueB, isAsync) = bridgeContract.convert{
      value: inputAssetA.assetType == AztecTypes.AztecAssetType.ETH
        ? totalInputValue
        : 0
    }(
      inputAssetA,
      inputAssetB,
      outputAssetA,
      outputAssetB,
      totalInputValue,
      interactionNonce,
      uint64(auxInputData)
    );

    if (
      outputAssetA.assetType != AztecTypes.AztecAssetType.VIRTUAL &&
      outputAssetA.assetType != AztecTypes.AztecAssetType.NOT_USED
    ) {
      require(
        outputValueA ==
          SafeMath.sub(getBalance(outputAssetA.erc20Address), tempValueA),
        "DefiBridgeProxy: INCORRECT_ASSET_VALUE"
      );
    }

    if (
      outputAssetB.assetType != AztecTypes.AztecAssetType.VIRTUAL &&
      outputAssetB.assetType != AztecTypes.AztecAssetType.NOT_USED
    ) {
      require(
        outputValueB ==
          SafeMath.sub(getBalance(outputAssetB.erc20Address), tempValueB),
        "DefiBridgeProxy: INCORRECT_ASSET_VALUE"
      );
    }

    if (isAsync) {
      require(
        outputValueA == 0 && outputValueB == 0,
        "DefiBridgeProxy: ASYNC_NONZERO_OUTPUT_VALUES"
      );
    }

    emit AztecBridgeInteraction(
      bridgeAddress,
      outputValueA,
      outputValueB,
      isAsync
    );
  }

  function canFinalise(address bridgeAddress, uint256 interactionNonce)
    external
    view
    returns (bool ready)
  {
    IDefiBridge bridgeContract = IDefiBridge(bridgeAddress);
    (ready) = bridgeContract.canFinalise(interactionNonce);
  }

  function finalise(
    address bridgeAddress,
    AztecTypes.AztecAsset calldata inputAssetA,
    AztecTypes.AztecAsset calldata inputAssetB,
    AztecTypes.AztecAsset calldata outputAssetA,
    AztecTypes.AztecAsset calldata outputAssetB,
    uint256 interactionNonce,
    uint256 auxInputData // (auxData)
  ) external returns (uint256 outputValueA, uint256 outputValueB) {
    uint256 tempValueA;
    uint256 tempValueB;
    if (outputAssetA.assetType != AztecTypes.AztecAssetType.VIRTUAL) {
      tempValueA = getBalance(outputAssetA.erc20Address);
    }

    if (outputAssetB.assetType != AztecTypes.AztecAssetType.VIRTUAL) {
      tempValueB = getBalance(outputAssetB.erc20Address);
    }

    IDefiBridge bridgeContract = IDefiBridge(bridgeAddress);

    require(
      bridgeContract.canFinalise(interactionNonce),
      "DefiBridgeProxy: NOT_READY"
    );

    (outputValueA, outputValueB) = bridgeContract.finalise(
      inputAssetA,
      inputAssetB,
      outputAssetA,
      outputAssetB,
      interactionNonce,
      uint64(auxInputData)
    );

    if (
      outputAssetA.assetType != AztecTypes.AztecAssetType.VIRTUAL &&
      outputAssetA.assetType != AztecTypes.AztecAssetType.NOT_USED
    ) {
      require(
        outputValueA ==
          SafeMath.sub(getBalance(outputAssetA.erc20Address), tempValueA),
        "DefiBridgeProxy: INCORRECT_ASSET_VALUE"
      );
    }

    if (
      outputAssetB.assetType != AztecTypes.AztecAssetType.VIRTUAL &&
      outputAssetB.assetType != AztecTypes.AztecAssetType.NOT_USED
    ) {
      require(
        outputValueB ==
          SafeMath.sub(getBalance(outputAssetB.erc20Address), tempValueB),
        "DefiBridgeProxy: INCORRECT_ASSET_VALUE"
      );
    }

    emit AztecBridgeInteraction(
      bridgeAddress,
      outputValueA,
      outputValueB,
      false
    );
  }

  // This example swaps DAI/WETH9 for single path swaps and DAI/USDC/WETH9 for multi path swaps.

  address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  address public constant WETH9 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

  // For this example, we will set the pool fee to 0.3%.
  uint24 public constant poolFee = 3000;

  function convertEthToExactDai() external payable {
      //require(daiAmount > 0, "Must pass non 0 DAI amount");
      //require(msg.value > 0, "Must pass non 0 ETH amount");

      console.log("Received request with value: %s", msg.value);
      ISwapRouter uniswapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
      console.log("Uniswap Router: ", address(uniswapRouter));
        
      uint256 deadline = block.timestamp + 15; // using 'now' for convenience, for mainnet pass deadline from frontend!
      address tokenIn = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
      address tokenOut = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
      uint24 fee = 3000;
      address recipient = address(this);
      uint256 amountOut = 1000000000000000000;
      uint256 amountInMaximum = msg.value;
      uint160 sqrtPriceLimitX96 = 0;
      
      ISwapRouter.ExactOutputSingleParams memory params = ISwapRouter.ExactOutputSingleParams(
          tokenIn,
          tokenOut,
          fee,
          recipient,
          deadline,
          amountOut,
          amountInMaximum,
          sqrtPriceLimitX96
      );
      
      uint256 amountSpent = uniswapRouter.exactOutputSingle{ value: msg.value }(params);
      console.log("Amount spent ", amountSpent);
      
  }
}
