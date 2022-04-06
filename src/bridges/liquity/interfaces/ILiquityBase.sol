// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.10;

import "./IPriceFeed.sol";


interface ILiquityBase {
    function priceFeed() external view returns (IPriceFeed);
}
