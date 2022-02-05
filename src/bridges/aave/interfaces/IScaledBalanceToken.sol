// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

interface IScaledBalanceToken {
    function scaledBalanceOf(address user) external view returns (uint256);

    function underlying() external view returns (address);
}
