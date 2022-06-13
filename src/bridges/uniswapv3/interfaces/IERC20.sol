// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

interface IERC20 {
    function approve(address spender, uint256 amount) external returns (bool);

    function balanceOf(address user) external view returns (uint256);

    function mint(address receiver, uint256 amount) external;

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external;

    function transfer(address to, uint256 amount) external;
}

interface IERC20Detailed is IERC20 {
    function decimals() external view returns (uint8);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);
}
