// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import {ERC20Burnable} from '@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol';
import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';

interface IZkVToken {
    function burn(uint256 amount) external;
}

contract ZkVToken is ERC20Burnable {
    address public immutable owner;
    uint8 public immutable setDecimals;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol) {
        owner = msg.sender;
        setDecimals = _decimals;
    }

    function decimals() public view virtual override returns (uint8) {
        return setDecimals;
    }

    function mint(address to, uint256 amount) external {
        require(owner == msg.sender, 'ZkAToken: INVALID OWNER');
        _mint(to, amount);
    }
}
