// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import {IERC20Detailed} from "./IERC20.sol";

interface IAToken is IERC20Detailed {
    function scaledBalanceOf(address user) external view returns (uint256);
}
