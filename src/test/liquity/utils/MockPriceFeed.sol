// SPDX-License-Identifier: GPL-2.0-only
pragma solidity >=0.8.0 <=0.8.10;

import '../../../bridges/liquity/interfaces/IPriceFeed.sol';

contract MockPriceFeed is IPriceFeed {
    uint256 public immutable lastGoodPrice;

    constructor(uint256 _price) {
        lastGoodPrice = _price;
    }

    function fetchPrice() external override returns (uint256) {
        return lastGoodPrice;
    }
}
