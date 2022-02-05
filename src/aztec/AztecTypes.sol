// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd

pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

library AztecTypes {
  enum AztecAssetType {
    NOT_USED,
    ETH,
    ERC20,
    VIRTUAL
  }

  struct AztecAsset {
    uint256 id;
    address erc20Address;
    AztecAssetType assetType;
  }
}
