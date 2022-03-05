// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <=0.8.10;

import "./ILiquityBase.sol";
import "./IStabilityPool.sol";
import "./ILQTYStaking.sol";


// Common interface for the Trove Manager.
interface ITroveManager is ILiquityBase {
    function getCurrentICR(address _borrower, uint _price) external view returns (uint);

    function liquidate(address _borrower) external;

    function redeemCollateral(
        uint _LUSDAmount,
        address _firstRedemptionHint,
        address _upperPartialRedemptionHint,
        address _lowerPartialRedemptionHint,
        uint _partialRedemptionHintNICR,
        uint _maxIterations,
        uint _maxFee
    ) external;

    function getEntireDebtAndColl(address _borrower) external view returns (
        uint debt, 
        uint coll, 
        uint pendingLUSDDebtReward, 
        uint pendingETHReward
    );

    function closeTrove(address _borrower) external;

    function getBorrowingRateWithDecay() external view returns (uint);

    function getTroveStatus(address _borrower) external view returns (uint);
    
    function checkRecoveryMode(uint _price) external view returns (bool);
}
