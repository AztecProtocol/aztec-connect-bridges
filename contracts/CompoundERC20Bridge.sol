// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.6 <0.8.0;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { IDefiBridge } from "./interfaces/IDefiBridge.sol";
import { Types } from "./Types.sol";

// import 'hardhat/console.sol';

interface ICERC20 {
  function mint(uint256) external returns (uint256);
  function redeem(uint256) external returns (uint256);
  function redeemUnderlying(uint256) external returns (uint);
}

contract CompoundERC20Bridge is IDefiBridge {
  using SafeMath for uint256;

  address public immutable rollupProcessor;
  ICERC20 cToken;

  constructor(address _rollupProcessor, address _cToken) public {
    rollupProcessor = _rollupProcessor;
    cToken = ICERC20(_cToken);
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
    require(msg.sender == rollupProcessor, "CompoundERC20Bridge: INVALID_CALLER");
    isAsync = false;

    require(inputAssetA.assetType != Types.AztecAssetType.ETH, "CompoundERC20Bridge: INVALID_INPUT_ASSET_TYPE");
    cToken.mint(inputValue);
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
