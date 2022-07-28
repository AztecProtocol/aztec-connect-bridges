// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

interface IYearnRegistry {
    function latestVault(address token) external view returns (address);

    function tokens(uint256 index) external view returns (address);

    function vaults(address token, uint256 index) external view returns (address);

    function numTokens() external view returns (uint256);

    function numVaults(address token) external view returns (uint256);
}
