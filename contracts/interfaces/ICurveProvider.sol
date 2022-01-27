// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

interface ICurveProvider {
  function get_registry() external view returns (address);
}
