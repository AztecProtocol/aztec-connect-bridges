// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.4;
interface IWrappedfCashFactory {
    function deployWrapper(uint16 _currencyId, uint40 _maturity) external returns (address);
    function computeAddress(uint16 _currencyId, uint40 _maturity) external view returns (address);
}