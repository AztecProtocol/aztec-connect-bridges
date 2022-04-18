// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface CashMarketInterface {
    function getActiveMaturities() external view returns (uint32[] memory);
}
