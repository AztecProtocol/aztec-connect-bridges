// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

interface IWETH {
  function deposit() external payable;

  function approve(address spender, uint256 amount) external returns (bool);

  function transfer(address to, uint256 amount) external returns (bool);

  function balanceOf(address user) external view returns (uint256);
}
