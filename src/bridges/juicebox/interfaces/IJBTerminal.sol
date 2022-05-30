// SPDX-License-Identifier: MIT
pragma solidity >=0.6.10 <=0.8.10;

import './IJBDirectory.sol';

interface IJBTerminal {
    function token() external view returns (address);

    function ethBalanceOf(uint256 _projectId) external view returns (uint256);

    function remainingDistributionLimitOf(
        uint256 _projectId,
        uint256 _fundingCycleConfiguration,
        uint256 _fundingCycleNumber
    ) external view returns (uint256);

    function delegate() external view returns (address);

    function pay(
        uint256 _projectId,
        address _beneficiary,
        uint256 _minReturnedTokens,
        bool _preferClaimedTokens,
        string calldata _memo,
        bytes calldata _delegateMetadata
    ) external payable;

    function addToBalanceOf(uint256 _projectId, string memory _memo) external payable;
}
