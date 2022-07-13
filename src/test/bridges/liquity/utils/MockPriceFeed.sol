// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IPriceFeed} from "../../../../interfaces/liquity/IPriceFeed.sol";

contract MockPriceFeed is IPriceFeed {
    // solhint-disable-next-line
    uint256 public immutable lastGoodPrice;

    constructor(uint256 _price) {
        lastGoodPrice = _price;
    }

    function fetchPrice() external override(IPriceFeed) returns (uint256) {
        return lastGoodPrice;
    }
}
