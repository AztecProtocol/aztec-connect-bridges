// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import {ILendingPool} from "../../../../interfaces/aave/ILendingPool.sol";
import {IPool} from "../../../../interfaces/aave/IPool.sol";
import {DataTypes} from "../../../../libraries/aave/DataTypes.sol";

contract AaveV3StorageEmulator is IPool {
    ILendingPool public immutable POOL;

    constructor(address _lendingPool) {
        POOL = ILendingPool(_lendingPool);
    }

    function getReserveData(address _asset) external view returns (DataTypes.ReserveDataV3 memory) {
        DataTypes.ReserveData memory v2Data = POOL.getReserveData(_asset);

        DataTypes.ReserveDataV3 memory data = DataTypes.ReserveDataV3({
            configuration: v2Data.configuration,
            liquidityIndex: v2Data.liquidityIndex,
            currentLiquidityRate: v2Data.currentLiquidityRate,
            variableBorrowIndex: v2Data.variableBorrowIndex,
            currentVariableBorrowRate: v2Data.currentVariableBorrowRate,
            currentStableBorrowRate: v2Data.currentStableBorrowRate,
            lastUpdateTimestamp: v2Data.lastUpdateTimestamp,
            id: uint16(v2Data.id),
            aTokenAddress: v2Data.aTokenAddress,
            stableDebtTokenAddress: v2Data.stableDebtTokenAddress,
            variableDebtTokenAddress: v2Data.variableDebtTokenAddress,
            interestRateStrategyAddress: v2Data.interestRateStrategyAddress,
            accruedToTreasury: 0,
            unbacked: 0,
            isolationModeTotalDebt: 0
        });

        return data;
    }
}
