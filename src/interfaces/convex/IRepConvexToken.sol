// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRepConvexToken is IERC20 {
    function mint(uint256 amount) external;

    function burn(uint256 amount) external;
}
