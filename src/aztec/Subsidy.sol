// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {ISubsidy} from "./interfaces/ISubsidy.sol";

/**
 * @title Subsidy
 * @notice A contract which allows anyone to subsidize a bridge
 * @author Jan Benes
 */
contract Subsidy is ISubsidy {
    error ArrayLengthsDontMatch();
    error AlreadySubsidized();
    error GasUsageNotSet();
    error SubsidyTooLow();
    error Overflow();

    struct Subsidy {
        uint128 available;
        uint64 gasUsage;
        uint32 lastUpdated;
        uint32 gasPerSecond;
    }

    // address bridge => uint256 criteria => Subsidy subsidy
    mapping(address => mapping(uint256 => Subsidy)) public subsidies;

    function setGasUsage(uint256 _criteria, uint64 _gasUsage) external {
        subsidies[msg.sender][_criteria].gasUsage = _gasUsage;
    }

    function setGasUsages(uint256[] calldata _criterias, uint64[] calldata _gasUsages) external {
        uint256 criteriasLength = _criterias.length;
        if (criteriasLength != _gasUsages.length) {
            revert ArrayLengthsDontMatch();
        }

        for (uint256 i; i < criteriasLength; ) {
            subsidies[msg.sender][_criterias[i]].gasUsage = _gasUsages[i];
            unchecked {
                ++i;
            }
        }
    }

    function subsidize(
        address _bridge,
        uint256 _criteria,
        uint32 _gasPerSecond
    ) external payable {
        // Caching subsidy in order to minimize number of SLOADs and SSTOREs
        Subsidy memory sub = subsidies[_bridge][_criteria];

        if (sub.available > 0) {
            revert AlreadySubsidized();
        }
        if (sub.gasUsage == 0) {
            revert GasUsageNotSet();
        }

        if (_gasPerSecond < sub.gasUsage / 7 days) {
            revert SubsidyTooLow();
        }
        if (msg.value > type(uint128).max) {
            // This condition could happen if subsidy was be bigger than ~340 ETH
            revert Overflow();
        }

        sub.available = uint128(msg.value);
        sub.lastUpdated = uint32(block.timestamp);
        sub.gasPerSecond = uint32(_gasPerSecond);

        subsidies[_bridge][_criteria] = sub;
    }

    function claimSubsidy(uint256 _criteria, address _beneficiary) external returns (uint256) {
        // Caching subsidy in order to minimize number of SLOADs and SSTOREs
        Subsidy memory sub = subsidies[msg.sender][_criteria];
        if (sub.available == 0) {
            return 0;
        }

        uint256 dt = block.timestamp - sub.lastUpdated;
        uint256 gasToCover = dt * sub.gasPerSecond;
        uint256 ethToCover = (gasToCover < sub.gasUsage ? gasToCover : sub.gasUsage) * block.basefee;
        uint256 subsidyAmount = (ethToCover < sub.available ? ethToCover : sub.available);

        sub.available -= uint128(subsidyAmount);
        sub.lastUpdated = uint32(block.timestamp);

        subsidies[msg.sender][_criteria] = sub;

        // Reverts, if beneficiary cannot receive funds
        _beneficiary.call{value: subsidyAmount, gas: 30000}("");

        return subsidyAmount;
    }
}
