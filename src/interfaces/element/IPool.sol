// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

import {IVault} from "./IVault.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

interface IPool is IERC20, IERC20Permit {
    /// @dev Returns the poolId for this pool
    /// @return The poolId for this pool
    function getPoolId() external view returns (bytes32);

    function underlying() external view returns (IERC20);

    function expiration() external view returns (uint256);

    function getVault() external view returns (IVault);
}
