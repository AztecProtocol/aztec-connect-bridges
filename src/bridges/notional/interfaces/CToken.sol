// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.4;

interface CToken {
    function exchangeRateCurrent() external returns (uint256);
}
