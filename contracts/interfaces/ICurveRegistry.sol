// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

interface ICurveRegistry {
  function pool_count() external view returns (uint256);
  function pool_list(uint256) external view returns (address);
  function get_n_coins(address) external view returns (uint256[2] memory);
  function get_underlying_coins(address) external view returns (address[8] memory);
  function get_coins(address) external view returns (address[8] memory);
  function get_lp_token(address) external view returns (address);
  function get_pool_from_lp_token(address) external view returns (address);
}