// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

interface ISafeManager {
    function openSAFE(
        bytes32 collateralType,
        address usr
    ) external returns (uint);

    function modifySAFECollateralization(
        uint safe,
        int deltaCollateral,
        int deltaDebt
    ) external;

    function transferInternalCoins(
        uint safe,
        address dst,
        uint rad
    ) external;

    function safes(uint _safeId) external view returns (address);

    function transferCollateral(
        uint safe,
        address dst,
        uint wad
    ) external;
}