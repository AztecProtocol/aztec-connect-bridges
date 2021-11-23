// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.6 <0.8.0;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { UniswapV2Library } from "@uniswap/v2-periphery/contracts/libraries/UniswapV2Library.sol";
import { IUniswapV2Router02 } from "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import { IDefiBridge } from "./interfaces/IDefiBridge.sol";
import { Types } from "./Types.sol";

// import 'hardhat/console.sol';

contract UniswapBridge is IDefiBridge {
  using SafeMath for uint256;

  address public immutable rollupProcessor;
  address public weth;

  IUniswapV2Router02 router;

  constructor(address _rollupProcessor, address _router) public {
    rollupProcessor = _rollupProcessor;
    router = IUniswapV2Router02(_router);
    weth = router.WETH();
  }

  receive() external payable {}

  function convert(
    Types.AztecAsset calldata inputAssetA,
    Types.AztecAsset calldata,
    Types.AztecAsset calldata outputAssetA,
    Types.AztecAsset calldata,
    uint256 inputValue,
    uint256,
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
    require(msg.sender == rollupProcessor, "UniswapBridge: INVALID_CALLER");
    isAsync = false;
    uint256[] memory amounts;
    uint256 deadline = block.timestamp;
    // TODO This should check the pair exists on UNISWAP instead of blindly trying to swap.

    if (
      inputAssetA.assetType == Types.AztecAssetType.ETH &&
      outputAssetA.assetType == Types.AztecAssetType.ERC20
    ) {
      address[] memory path = new address[](2);
      path[0] = weth;
      path[1] = outputAssetA.erc20Address;
      amounts = router.swapExactETHForTokens{ value: inputValue }(
        0,
        path,
        rollupProcessor,
        deadline
      );
      outputValueA = amounts[1];
    } else if (
      inputAssetA.assetType == Types.AztecAssetType.ERC20 &&
      outputAssetA.assetType == Types.AztecAssetType.ETH
    ) {
      address[] memory path = new address[](2);
      path[0] = inputAssetA.erc20Address;
      path[1] = weth;
      require(
        IERC20(inputAssetA.erc20Address).approve(address(router), inputValue),
        "UniswapBridge: APPROVE_FAILED"
      );
      amounts = router.swapExactTokensForETH(
        inputValue,
        0,
        path,
        rollupProcessor,
        deadline
      );
      outputValueA = amounts[1];
    } else {
      // TODO what about swapping tokens?
      revert("UniswapBridge: INCOMPATIBLE_ASSET_PAIR");
    }
  }

  function canFinalise(
    uint256 /*interactionNonce*/
  ) external view override returns (bool) {
    return false;
  }

  function finalise(
    Types.AztecAsset calldata,
    Types.AztecAsset calldata,
    Types.AztecAsset calldata,
    Types.AztecAsset calldata,
    uint256,
    uint64
  ) external payable override returns (uint256, uint256) {
    require(false);
  }
}
