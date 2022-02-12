// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import { IDefiBridge } from "../../interfaces/IDefiBridge.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AztecTypes } from "../../aztec/AztecTypes.sol";

import {ICoinJoin} from "./interfaces/ICoinJoin.sol";
import {IEthJoin} from "./interfaces/IEthJoin.sol";
import {ISafeEngine} from "./interfaces/ISafeEngine.sol";
import {ISafeManager} from "./interfaces/ISafeManager.sol";
import {IWeth} from "./interfaces/IWeth.sol";
import {AggregatorV3Interface} from "./interfaces/AggregatorV3Interface.sol";


// NOTE:
// 1. Theres a minimum amount of RAI to be borrowed in the first call, which is currently 1469 RAI

contract RaiBridge is IDefiBridge {
  using SafeMath for uint256;

  address public immutable rollupProcessor;
  AggregatorV3Interface internal priceFeed = AggregatorV3Interface(0x4ad7B025127e89263242aB68F0f9c4E5C033B489);
  address public constant SAFE_ENGINE = 0xCC88a9d330da1133Df3A7bD823B95e52511A6962;
  address public constant SAFE_MANAGER = 0xEfe0B4cA532769a3AE758fD82E1426a03A94F185;
  address public constant COIN_JOIN = 0x0A5653CCa4DB1B6E265F47CAf6969e64f1CFdC45;
  address public constant ETH_JOIN = 0x2D3cD7b81c93f188F3CB8aD87c8Acc73d6226e3A;
  address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
  address public constant RAI = 0x03ab458634910AaD20eF5f1C8ee96F1D6ac54919;

  address public immutable SAFE_HANDLER;

  uint public immutable safeId;
  uint public constant collateralRatio = 20000; // 200%, in BPS (divide by 10000) 

  constructor(address _rollupProcessor) public {
    rollupProcessor = _rollupProcessor;

    // OPEN THE SAFE
    safeId = ISafeManager(SAFE_MANAGER).openSAFE(0x4554482d41000000000000000000000000000000000000000000000000000000, address(this));

    SAFE_HANDLER = ISafeManager(SAFE_MANAGER).safes(safeId);

    // do all one off approvals
    require(IWeth(WETH).approve(ETH_JOIN, type(uint).max), "Weth approve failed");
    require(IERC20(RAI).approve(rollupProcessor, type(uint).max), "Rai approve failed");
    ISafeEngine(SAFE_ENGINE).approveSAFEModification(COIN_JOIN);   
  }

  function convert(
    AztecTypes.AztecAsset memory inputAssetA,
    AztecTypes.AztecAsset memory inputAssetB,
    AztecTypes.AztecAsset memory outputAssetA,
    AztecTypes.AztecAsset memory outputAssetB,
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
    // // ### INITIALIZATION AND SANITY CHECKS
    require(msg.sender == rollupProcessor, "RaiBridge: INVALID_CALLER");

    // rai only takes weth as collateral
    require( 
      inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 && 
      inputAssetA.erc20Address == WETH,
      "RaiBridge: INPUT_ASSET_NOT_ERC20"
    );

  // this may need to be change to integrate both repay and collateral in the same convert function
    require(
      outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 &&
      outputAssetA.erc20Address == RAI,
      "RaiBridge: OUTPUT_ASSET_NOT_ERC20"
    );

    IEthJoin(ETH_JOIN).join(SAFE_HANDLER, totalInputValue);

    // rai to Eth Ratio
     (, int x, , ,) = priceFeed.latestRoundData();

     uint raiToEth = uint(x);

    // expected RAI amount = eth_amount * (1e18/raiToEthPrice) * (1/collateralRatio)
     outputValueA = totalInputValue.mul(1e22).div(raiToEth).div(collateralRatio);

     ISafeManager(SAFE_MANAGER).modifySAFECollateralization(safeId, int(totalInputValue), int(outputValueA));

     ISafeManager(SAFE_MANAGER).transferInternalCoins(safeId, address(this), outputValueA * 10**27);

     ICoinJoin(COIN_JOIN).exit(address(this), outputValueA);
  } 


  function finalise(
    AztecTypes.AztecAsset calldata inputAssetA,
    AztecTypes.AztecAsset calldata inputAssetB,
    AztecTypes.AztecAsset calldata outputAssetA,
    AztecTypes.AztecAsset calldata outputAssetB,
    uint256 interactionNonce,
    uint64 auxData
  ) external payable override returns (uint256, uint256, bool) {
    require(false);
  }
}
