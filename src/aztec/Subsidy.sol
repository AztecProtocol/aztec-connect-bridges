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
    error ArrayLengthsDoNotMatch();
    error GasPerSecondTooLow();
    error AlreadySubsidized();
    error GasUsageNotSet();
    error SubsidyTooLow();
    error EthTransferFailed();

    struct Subsidy {
        uint64 gasUsage; // @dev minimum acceptable subsidy slope per 1 week - for how much gas is the
        uint128 available; // @dev amount of ETH remaining to be paid out
        uint32 lastUpdated; // @dev last time subsidy was paid out or funded (if not subsidy was yet claimed)
        uint32 gasPerSecond; // @dev how much gas per second is the funder willing to subsidize
    }

    // @dev Using min possible `msg.value` upon subsidizing in order to limit possibility of front running attacks
    // --> e.g. attacker front-running real subsidy tx by sending 1 wei value tx making the real one revert
    uint256 public constant MIN_SUBSIDY_VALUE = 1e17;

    // address bridge => uint256 criteria => Subsidy subsidy
    mapping(address => mapping(uint256 => Subsidy)) public subsidies;

    function setGasUsage(uint256 _criteria, uint64 _gasUsage) external {
        subsidies[msg.sender][_criteria].gasUsage = _gasUsage;
    }

    function setGasUsage(uint256[] calldata _criterias, uint64[] calldata _gasUsages) external {
        uint256 criteriasLength = _criterias.length;
        if (criteriasLength != _gasUsages.length) {
            revert ArrayLengthsDoNotMatch();
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

        if (_gasPerSecond < sub.gasUsage / 7 days) {
            revert GasPerSecondTooLow();
        }
        if (sub.available > 0) {
            revert AlreadySubsidized();
        }
        if (sub.gasUsage == 0) {
            revert GasUsageNotSet();
        }
        if (msg.value < MIN_SUBSIDY_VALUE) {
            revert SubsidyTooLow();
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
        // At maximum `sub.gasUsage` gets covered
        uint256 ethToCover = (gasToCover < sub.gasUsage ? gasToCover : sub.gasUsage) * block.basefee;
        uint256 subsidyAmount = (ethToCover < sub.available ? ethToCover : sub.available);

        sub.available -= uint128(subsidyAmount);
        sub.lastUpdated = uint32(block.timestamp);

        subsidies[msg.sender][_criteria] = sub;

        // Sending 30k gas in a call to allow fur receiver to be a multi-sig and write to storage
        (bool success, ) = _beneficiary.call{value: subsidyAmount, gas: 30000}("");
        if (!success) {
            // Reverts, if beneficiary is a contract and doesn't implement receive()/fallback()
            revert EthTransferFailed();
        }

        return subsidyAmount;
    }
}
