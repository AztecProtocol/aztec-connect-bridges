// SPDX-License-Identifier: GPL-2.0-only
pragma solidity >=0.8.4;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

interface IAccountingToken is IERC20Metadata {
    function burn(uint256 _amount) external;

    function mint(address _to, uint256 _amount) external;
}
