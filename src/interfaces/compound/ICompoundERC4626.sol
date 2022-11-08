// Note: only used in client
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICompoundERC4626 {
    function cToken() external view virtual returns (address);
}
