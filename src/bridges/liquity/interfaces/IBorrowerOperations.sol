// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.10;

interface IBorrowerOperations {
    function openTrove(uint _maxFee, uint _LUSDAmount, address _upperHint, address _lowerHint) external payable;

    function closeTrove() external;

    function adjustTrove(uint _maxFee, uint _collWithdrawal, uint _debtChange, bool isDebtIncrease, address _upperHint, address _lowerHint) external payable;

    function claimCollateral() external;
}
