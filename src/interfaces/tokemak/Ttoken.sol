// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface Ttoken is IERC20 {
    function requestedWithdrawals(address account) external view returns (uint256, uint256);

    function requestWithdrawal(uint256 amount) external;

    function deposit(uint256 amount) external payable;

    function withdraw(uint256 requestedAmount) external;

    function withdraw(uint256 requestedAmount, bool asEth) external;

    function underlyer() external view returns (address);
}
