// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

interface IAaveLendingBridgeConfigurator {
    function addNewPool(
        address _lendingBridge,
        address _underlyingAsset,
        address _aTokenAddress
    ) external;

    function addPoolFromV2(address _lendingBridge, address _underlyingAsset) external;

    function addPoolFromV3(address _lendingBridge, address _underlyingAsset) external;

    function claimLiquidityRewards(
        address _lendingBridge,
        address _incentivesController,
        address[] calldata _assets,
        address _beneficiary
    ) external returns (uint256);
}
