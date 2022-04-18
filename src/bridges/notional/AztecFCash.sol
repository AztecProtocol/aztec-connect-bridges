// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";


contract FCashToken is ERC20Burnable {
    address public immutable owner;
    uint8 public immutable setDecimals;
    uint public maturity;
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint _maturity 
    ) ERC20(_name, _symbol) {
        owner = msg.sender;
        setDecimals = _decimals;
        maturity = _maturity;
    }

    function decimals() public view virtual override returns (uint8) {
        return setDecimals;
    }

    function mint(address to, uint256 amount) external {
        require(owner == msg.sender, "ZkAToken: INVALID OWNER");
        _mint(to, amount);
    }
}