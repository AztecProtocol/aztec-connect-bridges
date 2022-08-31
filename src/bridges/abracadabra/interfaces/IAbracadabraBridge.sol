// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

interface IAbracadabraBridge {
    function setUnderlyingAToken(address _underlyingAsset, address _aTokenAddress) external;

    function Approve(address _underlyingAsset) external;

    function underlyingAToken(address _underlyingAsset) external view returns (address);
}
