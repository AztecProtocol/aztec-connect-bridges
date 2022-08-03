// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
pragma solidity >=0.8.4;

// @dev documentation of this interface is in its implementation (Subsidy contract)
interface ISubsidy {
    function setGasUsage(uint256 _criteria, uint64 _gasUsage) external;

    function setGasUsage(uint256[] calldata _criterias, uint64[] calldata _gasUsages) external;

    function subsidize(
        address _bridge,
        uint256 _criteria,
        uint32 _gasPerSecond
    ) external payable;

    function claimSubsidy(uint256 _criteria, address _beneficiary) external returns (uint256);

    function subsidies(address _bridge, uint256 _criteria)
        external
        returns (
            uint64,
            uint128,
            uint32,
            uint32
        );
}