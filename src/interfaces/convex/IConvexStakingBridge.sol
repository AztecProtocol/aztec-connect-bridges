// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

interface IConvexStakingBridge {
    function loadPool(uint256 poolId) external;

    function deployedClones(address curveLpToken) external returns (address);
}
