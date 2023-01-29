// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

interface ICurveExchangeV2 {
    function exchange(uint256 i, uint256 j, uint256 dx, uint256 min_dy, bool use_eth) external payable;
}
