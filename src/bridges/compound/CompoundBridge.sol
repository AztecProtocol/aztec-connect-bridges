// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.6.6 <0.8.10;
pragma experimental ABIEncoderV2;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IDefiBridge } from "../../interfaces/IDefiBridge.sol";
import { AztecTypes } from "../../aztec/AztecTypes.sol";
import "../../interfaces/IRollupProcessor.sol";

import "../../test/console.sol";

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
  function underlying() external returns (address);
}

contract CompoundBridge is IDefiBridge {

  address public immutable rollupProcessor;

  constructor(address _rollupProcessor) public {
    rollupProcessor = _rollupProcessor;

  }

  receive() external payable {}

  // ATC: To do: extend bridge to handle borrows and repays
  function convert(
    AztecTypes.AztecAsset calldata inputAssetA,
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata outputAssetA,
    AztecTypes.AztecAsset calldata,
    uint256 totalInputValue,
    uint256 interactionNonce,
    uint64 auxData,
    address
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
    isAsync = true;
    IERC20 underlying;

    // mint cETH case
    if (inputAssetA.assetType == AztecTypes.AztecAssetType.ETH){ 
      require(outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20, "CompoundBridge: INVALID_OUTPUT_ASSET_TYPE");
      ICETH cToken = ICETH(outputAssetA.erc20Address);
      cToken.mint{ value: msg.value }();
      outputValueB = cToken.balanceOf(address(this));
      cToken.approve(rollupProcessor,outputValueB);
      cToken.transfer(rollupProcessor,outputValueB);
    }

    // redeem cETH case
    else if (outputAssetA.assetType == AztecTypes.AztecAssetType.ETH){ 
      require(inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20, "CompoundBridge: INVALID_INPUT_ASSET_TYPE");
      ICETH cToken = ICETH(inputAssetA.erc20Address);
      outputValueB = address(this).balance;
      console.log("bridge balance before redeem = ", outputValueB);
      cToken.redeem(totalInputValue);
      console.log("bridge balance after redeem = ",address(this).balance);
      outputValueB = address(this).balance - outputValueB;
      console.log("ETH to send back via convert = ",outputValueB);
      IRollupProcessor(rollupProcessor).receiveEthFromBridge{value: outputValueB}(interactionNonce);
      //return(outputValueB,0,true); // ATC fixing failure on CircleCI
      return(0,0,true);
    }
    
    // mint or redeem cToken cases (auxData: 0 = mint, 1 = redeem)
    else{  
      require(inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20, "CompoundBridge: INVALID_INPUT_ASSET_TYPE");
      require(outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20, "CompoundBridge: INVALID_OUTPUT_ASSET_TYPE");
      if (auxData == 0) { // mint
        ICERC20 cToken = ICERC20(outputAssetA.erc20Address);
        underlying = IERC20(inputAssetA.erc20Address);
        require(underlying.balanceOf(address(this)) >= totalInputValue, "CompoundBridge: INSUFFICIENT_TOKEN_BALANCE");
        underlying.approve(address(cToken),totalInputValue);
        cToken.mint(totalInputValue);
        outputValueB = cToken.balanceOf(address(this));
        cToken.approve(rollupProcessor,outputValueB);
        cToken.transfer(rollupProcessor,outputValueB);
      }
      else if (auxData == 1) { // redeem
        ICERC20 cToken = ICERC20(inputAssetA.erc20Address);
        underlying = IERC20(outputAssetA.erc20Address);
        outputValueB = underlying.balanceOf(address(this));
        require(cToken.balanceOf(address(this)) >= totalInputValue, "CompoundBridge: INSUFFICIENT_CTOKEN_BALANCE"); 
        cToken.redeem(totalInputValue);
        outputValueB = underlying.balanceOf(address(this)) - outputValueB;
        underlying.approve(rollupProcessor,outputValueB);
        underlying.transfer(rollupProcessor,outputValueB);
      }
      else
        revert("CompoundBridge: UNRECOGNIZED_ACTION_REQUESTED");
    }
    return (0, 0, true);
  }

  ////ATC: This appears unnecessary for Compound...
  //function canFinalise(
  //  uint256 /*interactionNonce*/
  //) external view override returns (bool) {
  //  return false;
  //}

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
