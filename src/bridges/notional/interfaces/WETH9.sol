// SPDX-License-Identifier: MIT
<<<<<<< HEAD
pragma solidity >=0.8.4;
=======
pragma solidity >=0.7.6;
>>>>>>> ec73562e (add notional)

interface WETH9 {
    function deposit() external payable;

<<<<<<< HEAD
    function withdraw(uint256 _wad) external;

    function transfer(address _dst, uint256 _wad) external returns (bool);
=======
    function withdraw(uint256 wad) external;

    function transfer(address dst, uint wad) external returns (bool);
>>>>>>> ec73562e (add notional)
}
