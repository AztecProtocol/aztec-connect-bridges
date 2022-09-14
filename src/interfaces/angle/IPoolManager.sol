// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IPoolManager {
    struct StrategyParams {
        // Timestamp of last report made by this strategy
        // It is also used to check if a strategy has been initialized
        uint256 lastReport;
        // Total amount the strategy is expected to have
        uint256 totalStrategyDebt;
        // The share of the total assets in the `PoolManager` contract that the `strategy` can access to.
        uint256 debtRatio;
    }

    function strategies(address _strategy) external view returns (StrategyParams memory);

    function strategyList(uint256) external view returns (address);
}

interface IStrategy {
    function harvest() external;
}
