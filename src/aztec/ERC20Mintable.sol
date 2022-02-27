// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;

import { ERC20 } from "@openzeppelin/token/ERC20/ERC20.sol";

/**
 * @dev Warning: do not deploy in real environments, for testing only
 * ERC20 contract where anybody is able to mint
 */
contract ERC20Mintable is ERC20 {
  uint8 public asset_decimals = 18;

  constructor() public ERC20("Test", "TEST") {}

  function mint(address _to, uint256 _value) public returns (bool) {
    _mint(_to, _value);
    return true;
  }

  function decimals() public view virtual override returns (uint8) {
    return asset_decimals;
  }

  function setDecimals(uint8 _decimals) external {
    asset_decimals = _decimals;
  }
}
