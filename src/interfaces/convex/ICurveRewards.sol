// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

interface ICurveRewards {
    // Transfer ownership of staked Convex LP tokens from CurveRewards contract to the bridge
    function withdraw(uint256 amount, bool claim) external returns (bool);

    // Claim the earned rewards
    function getReward(address _account, bool _claimExtras) external returns (bool);

    function stakeFor(address _for, uint256 _amount) external returns(bool);

    function balanceOf(address account) external view returns (uint256);
}
