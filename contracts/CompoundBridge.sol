// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.6 <0.8.0;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol"; 

import { IDefiBridge } from "./interfaces/IDefiBridge.sol";
import { Types } from "./Types.sol";

interface ICETH {
  function mint() external payable;
  function redeem(uint) external returns (uint);
  function redeemUnderlying(uint) external returns (uint);
}

interface ICERC20 {
  function mint(uint256) external returns (uint256);
  function redeem(uint256) external returns (uint256);
  function redeemUnderlying(uint256) external returns (uint);
}

contract CompoundBridge is IDefiBridge {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  address public immutable rollupProcessor;

  // ATC more general approach: pull list of cToken markets from comptroller?
  // Here is cBAT for now:

  ICERC20 cBAT = ICERC20(0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E);
  //ICERC20 cToken = ICERC20();

  constructor(address _rollupProcessor) public {
    rollupProcessor = _rollupProcessor;
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
    require(msg.sender == rollupProcessor, "CompoundBridge: INVALID_CALLER");

    require(inputAssetA.assetType == Types.AztecAssetType.ERC20, "CompoundBridge: INVALID_INPUT_ASSET_TYPE");
    // ATC: add requirement inputAssetA.erc20Address must be in getAllMarkets

    require(outputAssetA.assetType == Types.AztecAssetType.ERC20, "CompoundBridge: INVALID_OUTPUT_ASSET_TYPE");
    // ATC: add requirement inputAssetA.erc20Address must be a cToken?

    isAsync = false;
 
    cBAT.mint(inputValue);

    // ATC: below is the correct alt syntax for cETH only
    //cEth.mint{ value: msg.value, gas: 250000 }();
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
