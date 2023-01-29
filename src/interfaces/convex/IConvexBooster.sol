// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

interface IConvexBooster {
    // Deposit lp tokens and stake
    function deposit(uint256 _pid, uint256 _amount, bool _stake) external returns (bool);

    // Withdraw lp tokens
    function withdraw(uint256 _pid, uint256 _amount) external returns (bool);

    // Number of Convex pools available
    function poolLength() external view returns (uint256);

    // Pool information
    function poolInfo(uint256) external view returns (address, address, address, address, address, bool);

    // Staker
    function staker() external view returns (address);

    // Minter
    function minter() external view returns (address);
}
