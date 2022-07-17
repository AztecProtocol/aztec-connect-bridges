// SPDX-License-Identifier: MIT
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
pragma solidity >=0.8.4;
=======
pragma solidity >=0.7.6;
>>>>>>> 37be3094 (add notional)
=======
pragma solidity >=0.8.4;
>>>>>>> 70661815 (add notional bridge)
=======
pragma solidity >=0.7.6;
>>>>>>> ec73562e (add notional)

interface WETH9 {
    function deposit() external payable;

<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
    function withdraw(uint256 _wad) external;

    function transfer(address _dst, uint256 _wad) external returns (bool);
=======
    function withdraw(uint256 wad) external;

    function transfer(address dst, uint wad) external returns (bool);
>>>>>>> 37be3094 (add notional)
=======
    function withdraw(uint256 _wad) external;

    function transfer(address _dst, uint _wad) external returns (bool);
>>>>>>> 70661815 (add notional bridge)
=======
    function withdraw(uint256 wad) external;

    function transfer(address dst, uint wad) external returns (bool);
>>>>>>> ec73562e (add notional)
}
