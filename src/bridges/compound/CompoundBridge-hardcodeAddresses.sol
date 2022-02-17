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

  // ATC more general approach: pull list of cToken markets from comptroller
  // Note: Hard-coding of comptroller address can be circumvented by
  //       adding a constructor that takes address as argument; see Aave
  //address[] cTokens;
  //ComptrollerInterface comptroller = ComptrollerInterface(0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B);
  //cTokens = comptroller.getAllMarkets;

  // Let's declare explicitly for now:

  ICERC20 cAAVE  = ICERC20(0xe65cdB6479BaC1e22340E4E755fAE7E509EcD06c);
  ICERC20 cBAT   = ICERC20(0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E);
  ICERC20 cCOMP  = ICERC20(0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4);
  ICERC20 cDAI   = ICERC20(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
  ICETH   cETH   =   ICETH(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
  ICERC20 cLINK  = ICERC20(0xFAce851a4921ce59e912d19329929CE6da6EB0c7);
  ICERC20 cMKR   = ICERC20(0x95b4eF2869eBD94BEb4eEE400a99824BF5DC325b);
  ICERC20 cSUSHI = ICERC20(0x4B0181102A0112A2ef11AbEE5563bb4a3176c9d7);
  ICERC20 cTUSD  = ICERC20(0x12392F67bdf24faE0AF363c24aC620a2f67DAd86);
  ICERC20 cUNI   = ICERC20(0x35A18000230DA775CAc24873d00Ff85BccdeD550);
  ICERC20 cUSDC  = ICERC20(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
  ICERC20 cUSDP  = ICERC20(0x041171993284df560249B57358F931D9eB7b925D);
  ICERC20 cUSDT  = ICERC20(0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9);
  ICERC20 cWBTC2 = ICERC20(0xccF4429DB6322D5C611ee964527D42E5d685DD6a);
  ICERC20 cYFI   = ICERC20(0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946);
  ICERC20 cZRX   = ICERC20(0xB3319f5D18Bc0D84dD1b4825Dcde5d5f7266d407);

  address AAVEaddress   = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;
  address BATaddress    = 0x0D8775F648430679A709E98d2b0Cb6250d2887EF;
  address COMPaddress   = 0xc00e94Cb662C3520282E6f5717214004A7f26888;
  address DAIaddress    = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
  address LINKaddress   = 0x514910771AF9Ca656af840dff83E8264EcF986CA;
  address MKRaddress    = 0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2;
  address SUSHIaddress  = 0x6B3595068778DD592e39A122f4f5a5cF09C90fE2;
  address TUSDaddress   = 0x0000000000085d4780B73119b644AE5ecd22b376;
  address UNIaddress    = 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984;
  address USDCaddress   = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
  address USDPaddress   = 0x8E870D67F660D95d5be530380D0eC0bd388289E1;
  address USDTaddress   = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
  address WBTCaddress   = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
  address YFIaddress    = 0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e;
  address ZRXaddress    = 0xE41d2489571d322189246DaFA5ebDe1F4699F498;
  address cAAVEaddress  = 0xe65cdB6479BaC1e22340E4E755fAE7E509EcD06c;
  address cBATaddress   = 0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E;
  address cCOMPaddress  = 0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4;
  address cDAIaddress   = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
  address cETHaddress   = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
  address cLINKaddress  = 0xFAce851a4921ce59e912d19329929CE6da6EB0c7;
  address cMKRaddress   = 0x95b4eF2869eBD94BEb4eEE400a99824BF5DC325b;
  address cSUSHIaddress = 0x4B0181102A0112A2ef11AbEE5563bb4a3176c9d7;
  address cTUSDaddress  = 0x12392F67bdf24faE0AF363c24aC620a2f67DAd86;
  address cUNIaddress   = 0x35A18000230DA775CAc24873d00Ff85BccdeD550;
  address cUSDCaddress  = 0x39AA39c021dfbaE8faC545936693aC917d5E7563;
  address cUSDPaddress  = 0x041171993284df560249B57358F931D9eB7b925D;
  address cUSDTaddress  = 0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9;
  address cWBTC2address = 0xccF4429DB6322D5C611ee964527D42E5d685DD6a;
  address cYFIaddress   = 0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946;
  address cZRXaddress   = 0xB3319f5D18Bc0D84dD1b4825Dcde5d5f7266d407;


  constructor(address _rollupProcessor) public {
    rollupProcessor = _rollupProcessor;
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

    // ATC: is isAsync my issue?
    isAsync = false;
    //isAsync = true;
 
    if (inputAssetA.assetType == AztecTypes.AztecAssetType.ETH){
      cETH.mint{ value: msg.value }();
      outputValueB = cETH.balanceOf(address(this));
      cETH.approve(rollupProcessor,outputValueB);
      cETH.transfer(rollupProcessor,outputValueB);
    }
    else{
      require(inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20, "CompoundBridge: INVALID_INPUT_ASSET_TYPE");
      if (inputAssetA.erc20Address == BATaddress){
        require(IERC20(BATaddress).balanceOf(address(this)) >= totalInputValue, "CompoundBridge: INSUFFICIENT_TOKEN_BALANCE");
        IERC20(BATaddress).approve(cBATaddress,totalInputValue);
        outputValueB = cBAT.mint(totalInputValue);
        outputValueA = IERC20(cBATaddress).balanceOf(address(this));
      }
      else if (inputAssetA.erc20Address == UNIaddress){
        //console.log("Entering UNI logic in CompoundBridge.convert()");
        require(IERC20(UNIaddress).balanceOf(address(this)) >= totalInputValue, "CompoundBridge: INSUFFICIENT_TOKEN_BALANCE");
        //console.log("Let's approve the cUNI contract to spend the bridge's UNI");
        IERC20(UNIaddress).approve(cUNIaddress,totalInputValue);
        //console.log("Let's mint cUNI with the bridge's UNI");
        //console.log(totalInputValue);
        outputValueB = cUNI.mint(totalInputValue);
        outputValueA = IERC20(cUNIaddress).balanceOf(rollupProcessor);
      }
      else if (inputAssetA.erc20Address == DAIaddress){
        require(IERC20(DAIaddress).balanceOf(address(this)) >= totalInputValue, "CompoundBridge: INSUFFICIENT_TOKEN_BALANCE");
        IERC20(DAIaddress).approve(cDAIaddress,totalInputValue);
        //outputValueB = cDAI.mint(totalInputValue);
        cDAI.mint(totalInputValue);
        outputValueB = cDAI.balanceOf(address(this));
        //outputValueA = IERC20(cDAIaddress).balanceOf(address(this));
        //outputValueA = 0;
        cDAI.approve(rollupProcessor,outputValueB);
        cDAI.transfer(rollupProcessor,outputValueB);
      }
      else if (inputAssetA.erc20Address == MKRaddress){
        require(IERC20(MKRaddress).balanceOf(address(this)) >= totalInputValue, "CompoundBridge: INSUFFICIENT_TOKEN_BALANCE");
        IERC20(MKRaddress).approve(cMKRaddress,totalInputValue);
        outputValueB = cMKR.mint(totalInputValue);
        outputValueA = IERC20(cMKRaddress).balanceOf(address(this));
        outputValueA = 0;
      }
    }
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
