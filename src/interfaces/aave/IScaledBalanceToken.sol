// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.6.10;

interface IScaledBalanceToken {
    function scaledBalanceOf(address user) external view returns (uint256);

    function underlying() external view returns (address);
}
