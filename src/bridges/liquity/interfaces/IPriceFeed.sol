// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IPriceFeed {
    function fetchPrice() external returns (uint256);
}
