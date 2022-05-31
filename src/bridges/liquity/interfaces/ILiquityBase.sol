// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {IPriceFeed} from "./IPriceFeed.sol";

interface ILiquityBase {
    function priceFeed() external view returns (IPriceFeed);
}
