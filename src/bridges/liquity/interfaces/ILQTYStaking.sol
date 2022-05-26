// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.10;

interface ILQTYStaking {
    function stakes(address _user) external view returns (uint256);

    function stake(uint256 _LQTYamount) external;

    function unstake(uint256 _LQTYamount) external;
}
