// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import {ILendingPoolAddressesProvider} from "./../../../../interfaces/aave/ILendingPoolAddressesProvider.sol";

interface IAaveLendingBridge {
    function setUnderlyingToZkAToken(address _underlyingAsset, address _aTokenAddress) external;

    function performApprovals(address _underlyingAsset) external;

    function claimLiquidityRewards(
        address _incentivesController,
        address[] calldata _assets,
        address _beneficiary
    ) external returns (uint256);

    function ROLLUP_PROCESSOR() external view returns (address);

    function ADDRESSES_PROVIDER() external view returns (ILendingPoolAddressesProvider);

    function CONFIGURATOR() external view returns (address);

    /// Mapping underlying assets to the zk atoken used for accounting
    function underlyingToZkAToken(address _underlyingAsset) external view returns (address);
}
