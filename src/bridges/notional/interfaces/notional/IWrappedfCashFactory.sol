// SPDX-License-Identifier: GPL-3.0-only
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
pragma solidity >=0.8.4;

interface IWrappedfCashFactory {
    function deployWrapper(uint16 _currencyId, uint40 _maturity) external returns (address);

    function computeAddress(uint16 _currencyId, uint40 _maturity) external view returns (address);
=======
=======
>>>>>>> ec73562e (add notional)
pragma solidity >=0.7.6;

interface IWrappedfCashFactory {
    function deployWrapper(uint16 currencyId, uint40 maturity) external returns (address);
    function computeAddress(uint16 currencyId, uint40 maturity) external view returns (address);
<<<<<<< HEAD
>>>>>>> 37be3094 (add notional)
=======
pragma solidity >=0.8.4;
interface IWrappedfCashFactory {
    function deployWrapper(uint16 _currencyId, uint40 _maturity) external returns (address);
    function computeAddress(uint16 _currencyId, uint40 _maturity) external view returns (address);
>>>>>>> 70661815 (add notional bridge)
=======
>>>>>>> ec73562e (add notional)
}
