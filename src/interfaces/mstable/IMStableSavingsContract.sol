// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

interface IMStableSavingsContract {
    function depositSavings(uint256 _underlying) external returns (uint256 creditsIssued);

    function redeemUnderlying(uint256 _underlying) external returns (uint256 creditsBurned);

    function balanceOf(address account) external returns (uint256);

    function redeemCredits(uint256 _credits) external returns (uint256 massetReturned);

    function exchangeRate() external view returns (uint256 exchangeRate);
}
