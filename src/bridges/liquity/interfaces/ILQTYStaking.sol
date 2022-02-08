// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.10;

interface ILQTYStaking {
    function stakes(address _user) external view returns (uint);

    function stake(uint _LQTYamount) external;

    function unstake(uint _LQTYamount) external;
}
