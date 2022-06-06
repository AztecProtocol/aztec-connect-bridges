// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {IAccountingToken} from "./interfaces/IAccountingToken.sol";

/**
 * @notice ERC20 token implementation that allow the owner to mint tokens and let anyone burn their own tokens
 * or token they have allowance to.
 * @dev The owner is immutable and therefore cannot be updated
 * @author Lasse Herskind
 */
contract AccountingToken is IAccountingToken, ERC20Burnable {
    error InvalidCaller();

    address public immutable OWNER;
    uint8 internal immutable TOKEN_DECIMALS;

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol) {
        OWNER = msg.sender;
        TOKEN_DECIMALS = _decimals;
    }

    /**
     * @notice Decimal getter
     * @return The number of decimals for the token
     */
    function decimals() public view virtual override(IERC20Metadata, ERC20) returns (uint8) {
        return TOKEN_DECIMALS;
    }

    /**
     * @notice Mint tokens to address
     * @dev Only callable by the owner
     * @param to The receiver of tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address to, uint256 amount) external override(IAccountingToken) {
        if (msg.sender != OWNER) {
            revert InvalidCaller();
        }
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens of caller
     * @dev Included to satisfy interface
     * @param amount The amount of tokens to burn from own account
     */
    function burn(uint256 amount) public virtual override(IAccountingToken, ERC20Burnable) {
        super.burn(amount);
    }
}
