// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

interface ILendingPoolAddressesProvider {
    function getLendingPool() external view returns (address);

    function setAddress(bytes32 id, address newAddress) external;

    function owner() external view returns (address);
}
