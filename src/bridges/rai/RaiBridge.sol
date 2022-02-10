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

contract RaiBridge is IDefiBridge {
  using SafeMath for uint256;

  address public immutable rollupProcessor;
  address public constant SAFE_ENGINE = 0xCC88a9d330da1133Df3A7bD823B95e52511A6962;
  address public constant SAFE_MANAGER = 0xEfe0B4cA532769a3AE758fD82E1426a03A94F185;
  address public constant COIN_JOIN = 0x0A5653CCa4DB1B6E265F47CAf6969e64f1CFdC45;
  address public constant ETH_JOIN = 0x2D3cD7b81c93f188F3CB8aD87c8Acc73d6226e3A;
  address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

  address public immutable SAFE_HANDLER;

  uint public immutable safe_id;
  uint public constant collateral_ratio = 20000; // 200%, in BPS (divide by 10000) 

  constructor(address _rollupProcessor) public {
    rollupProcessor = _rollupProcessor;

    // OPEN THE SAFE
    safe_id = ISafeManager(SAFE_MANAGER).openSAFE(0x4554482d41000000000000000000000000000000000000000000000000000000, address(this));

    SAFE_HANDLER = ISafeManager(SAFE_MANAGER).safes(safe_id);

    // do all one off approvals
    require(IWeth(WETH).approve(ETH_JOIN, type(uint).max), "Weth approve failed");
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
    require(msg.sender == rollupProcessor, "ExampleBridge: INVALID_CALLER");
    IERC20(inputAssetA.erc20Address).approve(rollupProcessor, totalInputValue);

    // rai only takes weth as collateral
    require( 
      inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 && 
      inputAssetA.erc20Address == WETH,
      "RaiBridge: INPUT_ASSET_NOT_ERC20"
    );

    IEthJoin(ETH_JOIN).join(SAFE_HANDLER, totalInputValue);


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
