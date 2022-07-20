// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

interface WETH9 {
    function deposit() external payable;

    function withdraw(uint256 _wad) external;

    function transfer(address _dst, uint _wad) external returns (bool);
}
