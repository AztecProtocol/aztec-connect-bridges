// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.4;
<<<<<<< HEAD

interface IWrappedfCashFactory {
    function deployWrapper(uint16 _currencyId, uint40 _maturity) external returns (address);

=======
interface IWrappedfCashFactory {
    function deployWrapper(uint16 _currencyId, uint40 _maturity) external returns (address);
>>>>>>> 70661815 (add notional bridge)
    function computeAddress(uint16 _currencyId, uint40 _maturity) external view returns (address);
}
