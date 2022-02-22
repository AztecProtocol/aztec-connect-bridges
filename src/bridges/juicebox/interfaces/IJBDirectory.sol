// SPDX-License-Identifier: MIT
pragma solidity >=0.6.10 <=0.8.10;

import './IJBTerminal.sol';

interface IJBDirectory {
    function primaryTerminalOf(uint256 _projectId, address _token) external view returns (IJBTerminal);
}
