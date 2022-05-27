// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import './IPriceFeed.sol';

interface ILiquityBase {
    function priceFeed() external view returns (IPriceFeed);
}
