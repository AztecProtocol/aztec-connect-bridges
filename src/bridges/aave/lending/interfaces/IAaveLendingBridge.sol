// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import {ILendingPoolAddressesProvider} from "./../../imports/interfaces/ILendingPoolAddressesProvider.sol";

interface IAaveLendingBridge {
    function setUnderlyingToZkAToken(address underlyingAsset, address aTokenAddress) external;

    function performApprovals(address underlyingAsset) external;

    function claimLiquidityRewards(
        address incentivesController,
        address[] calldata assets,
        address beneficiary
    ) external returns (uint256);

    function ROLLUP_PROCESSOR() external view returns (address);

    function ADDRESSES_PROVIDER() external view returns (ILendingPoolAddressesProvider);

    function CONFIGURATOR() external view returns (address);

    /// Mapping underlying assets to the zk atoken used for accounting
    function underlyingToZkAToken(address underlyingAsset) external view returns (address);
}
