// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

interface ICurveZap {
  function add_liquidity(
    address,
    uint256[2] calldata,
    uint256,
    address
  ) external payable;

  function add_liquidity(
    address,
    uint256[3] calldata,
    uint256,
    address
  ) external payable;

  function add_liquidity(
    address,
    uint256[4] calldata,
    uint256,
    address
  ) external payable;
}
