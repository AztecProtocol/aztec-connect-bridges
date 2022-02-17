// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.6 <0.8.10;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IDefiBridge } from "../../interfaces/IDefiBridge.sol";
import { AztecTypes } from "../../aztec/AztecTypes.sol";

//import { ComptrollerInterface } from "./interfaces/ComptrollerInterface.sol";

interface ICETH {
  function approve(address, uint) external returns (uint);
  function balanceOf(address) external view returns (uint256);
  function exchangeRateStored() external view returns (uint256);
  function transfer(address,uint) external returns (uint);
  function mint() external payable;
  function redeem(uint) external returns (uint);
  function redeemUnderlying(uint) external returns (uint);
}

interface ICERC20 {
  function accrueInterest() external;
  function approve(address, uint) external returns (uint);
  function balanceOf(address) external view returns (uint256);
  function balanceOfUnderlying(address) external view returns (uint256);
  function exchangeRateStored() external view returns (uint256);
  function transfer(address,uint) external returns (uint);
  function mint(uint256) external returns (uint256);
  function redeem(uint) external returns (uint);
  function redeemUnderlying(uint) external returns (uint);
}

contract CompoundBridgeContract is IDefiBridge {
  using SafeMath for uint256;

  address public immutable rollupProcessor;
  address public cTokenAddress;
  //address public cToken;
  //address public underlying;

  constructor(address _rollupProcessor, address _cTokenAddress) public {
    rollupProcessor = _rollupProcessor;
    cTokenAddress = _cTokenAddress;
  }

  receive() external payable {}

  function convert(
    AztecTypes.AztecAsset memory inputAssetA,
    AztecTypes.AztecAsset memory,
    AztecTypes.AztecAsset memory outputAssetA,
    AztecTypes.AztecAsset memory,
    uint256 totalInputValue,
    uint256 interactionNonce,
    uint64 auxData
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
    require(msg.sender == rollupProcessor, "CompoundBridge: INVALID_CALLER");
    require(outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20, "CompoundBridge: INVALID_OUTPUT_ASSET_TYPE");

    isAsync = false;
    ICERC20 cToken;
    IERC20 underlying;

    if (inputAssetA.assetType == AztecTypes.AztecAssetType.ETH){
      ICETH cToken = ICETH(outputAssetA.erc20Address);
      cToken.mint{ value: msg.value }();
    }
    else{
      cToken = ICERC20(outputAssetA.erc20Address);
      require(inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20, "CompoundBridge: INVALID_INPUT_ASSET_TYPE");
      underlying = IERC20(inputAssetA.erc20Address);
      require(underlying.balanceOf(address(this)) >= totalInputValue, "CompoundBridge: INSUFFICIENT_TOKEN_BALANCE");
      underlying.approve(address(cToken),totalInputValue);
      cToken.mint(totalInputValue);
    }
    outputValueB = cToken.balanceOf(address(this));
    cToken.approve(rollupProcessor,outputValueB);
    cToken.transfer(rollupProcessor,outputValueB);
  return (outputValueA, 0, true);
  }

//  ATC: This appears no longer necessary?
//  function canFinalise(
//    uint256 /*interactionNonce*/
//  ) external view override returns (bool) {
//    return false;
//  }

  function finalise(
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata outputAssetA,
    AztecTypes.AztecAsset calldata,
    uint256 interactionNonce,
    uint64
  ) external payable returns (uint256 outputValueA, uint256 outputValueB, bool interactionComplete) {
    require(msg.sender == rollupProcessor, "CompoundBridge: INVALID_CALLER");
  }
}
