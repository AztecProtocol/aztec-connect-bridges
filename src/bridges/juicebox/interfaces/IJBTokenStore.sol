// SPDX-License-Identifier: MIT
pragma solidity >=0.6.10 <=0.8.10;

import './IJBToken.sol';

interface IJBTokenStore {
    function tokenOf(uint256 _projectId) external view returns (IJBToken);
}
