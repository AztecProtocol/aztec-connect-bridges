// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

interface ISafeManager {
    function openSAFE(bytes32 collateralType, address usr) external returns (uint256);

    function modifySAFECollateralization(
        uint256 safe,
        int256 deltaCollateral,
        int256 deltaDebt
    ) external;

    function transferInternalCoins(
        uint256 safe,
        address dst,
        uint256 rad
    ) external;

    function safes(uint256 _safeId) external view returns (address);

    function transferCollateral(
        uint256 safe,
        address dst,
        uint256 wad
    ) external;
}
