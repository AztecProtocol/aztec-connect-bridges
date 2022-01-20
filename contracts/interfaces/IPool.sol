// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity >=0.7.5;
pragma abicoder v2;

import { IERC20Permit } from "./IERC20Permit.sol";

interface IPool is IERC20Permit{
    /// @dev Returns the poolId for this pool
    /// @return The poolId for this pool
    function getPoolId() external view returns (bytes32);
}