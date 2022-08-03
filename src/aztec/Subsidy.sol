// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {ISubsidy} from "./interfaces/ISubsidy.sol";

/**
 * @title Subsidy
 * @notice A contract which allows anyone to subsidize a bridge
 * @author Jan Benes
 * @dev The goal of this contract is to allow anyone to subsidize a bridge. How the subsidy works is that when a bridge
 *      is subsidized it can call `claimSubsidy(...)` method and in that method the corresponding subsidy gets sent to
 *      the beneficiary. Beneficiary is expected to be the rollup provider or an address controlled by the rollup
 *      provider. When sufficient subsidy is present it makes it profitable for the rollup provider to execute
 *      a bridge call even when only a small amounts of user fees can be extracted. This effectively makes it possible
 *      for calls to low-use bridges to be included in a rollup block called. Without subsidy, it might happen that
 *      UX of these brides would dramatically deteriorate since user might wait for a long time before her/his bridge
 *      call gets processed.
 *
 *      The subsidy is defined by a `gasPerSecond` amount and along with time since last interaction and the current
 *      base fee will be used to compute the amount of Eth that should be paid out to the rollup beneficiary.
 *      The subsidy will only ever grow to `Subsidy.gasUsage` gas. This value is the expected weekly gas usage
 *      of the bridge. Since only the base-fee is used, there will practically not be a free bridge interaction
 *      as the priority fee is paid on top However the fee could be tiny in comparison -> over time user fee goes
 *      toward just paying the priority fee/tip. Making the subsidy payout dependent upon the time since last bridge
 *      call/interaction makes the probability of the bridge call being executed grow with time.
 *
 *      `Subsidy.gasUsage` is not only used to define max subsidy payout but we also use it to compute minimum
 *      acceptable value of `Subsidy.gasPerSecond'. This is necessary because only 1 subsidy can be present at one time
 *      and not doing the check would open an opportunity for a griefing attack - attacker setting low subsidy which
 *      would take a long time to run out and effectively making it impossible for a legitimate subsidizer to subsidize
 *      a bridge.
 *
 *      Since we want to allow subsidizer to subsidize only a specific bridge call/interaction and not all
 *      calls/interactions we use identifier called `criteria` to distinguish different calls. `criteria` value
 *      is computed based on the inputs of `IDefiBridge.convert(...)` function and this computation is expected to be
 *      different in different bridges (e.g. Uniswap bridge might compute this value based on `_inputAssetA`,
 *      `_outputAssetA` and a path defined in `_auxData`).
 */
contract Subsidy is ISubsidy {
    error ArrayLengthsDoNotMatch();
    error GasPerSecondTooLow();
    error AlreadySubsidized();
    error GasUsageNotSet();
    error SubsidyTooLow();
    error EthTransferFailed();

    struct Subsidy {
        uint64 gasUsage; // @dev minimum subsidizable gas usage per 1 week
        uint128 available; // @dev amount of ETH remaining to be paid out
        uint32 lastUpdated; // @dev last time subsidy was paid out or funded (if not subsidy was yet claimed)
        uint32 gasPerSecond; // @dev how much gas per second is the funder willing to subsidize
    }

    // @dev Using min possible `msg.value` upon subsidizing in order to limit possibility of front running attacks
    // --> e.g. attacker front-running real subsidy tx by sending 1 wei value tx making the real one revert
    uint256 public constant MIN_SUBSIDY_VALUE = 1e17;

    // address bridge => uint256 criteria => Subsidy subsidy
    mapping(address => mapping(uint256 => Subsidy)) public subsidies;

    /**
     * @notice Sets `Subsidy.gasUsage` value for a given criteria
     * @dev This function has to be called from the bridge
     * @param _criteria A value defining a specific bridge call
     * @param _gasUsage An estimated weekly gas usage of a specific bridge call/interaction
     */
    function setGasUsage(uint256 _criteria, uint64 _gasUsage) external {
        subsidies[msg.sender][_criteria].gasUsage = _gasUsage;
    }

    /**
     * @notice Sets multiple `Subsidy.gasUsage` values for multiple criteria values
     * @dev This function has to be called from the bridge
     * @param _criterias An array of values each defining a specific bridge call
     * @param _gasUsages An array of estimated weekly gas usage values corresponding to criteria values defined
     *                  at the same index in `_criterias` array
     */
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

    /**
     * @notice Sets subsidy for a given `_bridge` and `_criteria`
     * @param _bridge Address of the bridge to subsidize
     * @param _criteria A value defining a specific bridge call
     * @param _gasPerSecond A value defining a "speed" at which the subsidy will be released
     * @dev reverts if any of these is true: 1) `_gasPerSecond` <= `Subsidy.gasUsage` divided by seconds in a week,
     *                                       2) subsidy funded before and not yet drained: `subsidy.available` > 0,
     *                                       3) subsidy.gasUsage not set: `subsidy.gasUsage` == 0,
     *                                       4) ETH value sent too low: `msg.value` < `MIN_SUBSIDY_VALUE`.
     */
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

    /**
     * @notice Computes and sends subsidy
     * @param _criteria A value defining a specific bridge call
     * @param _beneficiary Address which is going to receive the subsidy
     * @return subsidy ETH amount which was sent to the `_beneficiary`
     */
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
