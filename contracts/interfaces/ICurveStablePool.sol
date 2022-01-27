// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

interface ICurveStablePool {
  function add_liquidity(uint256[2] calldata, uint256) external payable;

  function add_liquidity(uint256[3] calldata, uint256) external payable;

  function add_liquidity(uint256[4] calldata, uint256) external payable;
}
