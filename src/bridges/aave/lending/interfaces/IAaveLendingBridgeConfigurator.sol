// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

interface IAaveLendingBridgeConfigurator {
    function addNewPool(
        address lendingBridge,
        address underlyingAsset,
        address aTokenAddress
    ) external;

    function addPoolFromV2(address lendingBridge, address underlyingAsset) external;

    function addPoolFromV3(address lendingBridge, address underlyingAsset) external;

    function claimLiquidityRewards(
        address lendingBridge,
        address incentivesController,
        address[] calldata assets,
        address beneficiary
    ) external returns (uint256);
}
