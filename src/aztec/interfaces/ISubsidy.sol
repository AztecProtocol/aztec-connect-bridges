// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
pragma solidity >=0.8.4;

// @dev documentation of this interface is in its implementation (Subsidy contract)
interface ISubsidy {
    function setGasUsageAndMinGasPerMinute(
        uint256 _criteria,
        uint32 _gasUsage,
        uint32 _minGasPerMinute
    ) external;

    function setGasUsageAndMinGasPerMinute(
        uint256[] calldata _criteria,
        uint32[] calldata _gasUsage,
        uint32[] calldata _minGasPerMinute
    ) external;

    function subsidize(
        address _bridge,
        uint256 _criteria,
        uint32 _gasPerMinute
    ) external payable;

    function claimSubsidy(uint256 _criteria, address _beneficiary) external returns (uint256);

    function subsidies(address _bridge, uint256 _criteria)
        external
        returns (
            uint128,
            uint32,
            uint32,
            uint32,
            uint32
        );
}
