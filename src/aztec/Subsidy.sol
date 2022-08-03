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
 *      provider. When sufficient subsidy is present it makes it profitable for the rollup provider to execute a bridge
 *      call even when only a small amounts of user fees can be extracted. This effectively makes it possible for calls
 *      to low-use bridges to be included in a rollup block. Without subsidy, it might happen that UX of these brides
 *      would dramatically deteriorate since user might wait for a long time before her/his bridge call gets processed.
 *
 *      The subsidy is defined by a `gasPerMinute` amount and along with time since last interaction and the current
 *      base fee will be used to compute the amount of Eth that should be paid out to the rollup beneficiary.
 *      The subsidy will only ever grow to `Subsidy.gasUsage` gas. This value is the expected gas usage of the specific
 *      bridge interaction. Since only the base-fee is used, there will practically not be a free bridge interaction
 *      because the priority fee is paid on top. However the fee could be tiny in comparison -> over time user fee goes
 *      toward just paying the priority fee/tip. Making the subsidy payout dependent upon the time since last bridge
 *      call/interaction makes the probability of the bridge call being executed grow with time.
 *
 *      `Subsidy.minGasPerMinute` is used to define minimum acceptable value of `Subsidy.gasPerMinute' when subsidy
 *      is created. This is necessary because only 1 subsidy can be present at one time and not doing the check would
 *      open an opportunity for a griefing attack - attacker setting low subsidy which would take a long time to run
 *      out and effectively making it impossible for a legitimate subsidizer to subsidize a bridge.
 *
 *      Since we want to allow subsidizer to subsidize only a specific bridge call/interaction and not all
 *      calls/interactions we use identifier called `criteria` to distinguish different calls. `criteria` value
 *      is computed based on the inputs of `IDefiBridge.convert(...)` function and this computation is expected to be
 *      different in different bridges (e.g. Uniswap bridge might compute this value based on `_inputAssetA`,
 *      `_outputAssetA` and a path defined in `_auxData`).
 */
contract Subsidy is ISubsidy {
    error ArrayLengthsDoNotMatch();
    error GasPerMinuteTooLow();
    error AlreadySubsidized();
    error GasUsageNotSet();
    error SubsidyTooLow();
    error EthTransferFailed();

    /**
     * @notice Container for Subsidy related information
     * @member available Amount of ETH remaining to be paid out
     * @member gasUsage Amount of gas the interaction consumes (used to define max possible payout)
     * @member minGasPerMinute Minimum amount of gas per second the subsidizer has to subsidize
     * @member gasPerMinute Amount of gas per second the subsidizer is willing to subsidize
     * @member lastUpdated Last time subsidy was paid out or funded (if not subsidy was yet claimed after funding)
     */
    struct Subsidy {
        uint128 available;
        uint32 gasUsage;
        uint32 minGasPerMinute;
        uint32 gasPerMinute;
        uint32 lastUpdated;
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
     * @param _minGasPerMinute Minimum amount of gas per second the subsidizer has to subsidize
     */
    function setGasUsageAndMinGasPerMinute(
        uint256 _criteria,
        uint32 _gasUsage,
        uint32 _minGasPerMinute
    ) external {
        subsidies[msg.sender][_criteria] = Subsidy(0, _gasUsage, _minGasPerMinute, 0, 0);
    }

    /**
     * @notice Sets multiple `Subsidy.gasUsage` values for multiple criteria values
     * @dev This function has to be called from the bridge
     * @param _criteria An array of values each defining a specific bridge call
     * @param _gasUsage An array of estimated weekly gas usage values corresponding to criteria values defined
     *                  at the same index in `_criterias` array
     * @param _minGasPerMinute An array of minimum gas per second amounts the subsidizer has to subsidize corresponding
     *                         to criteria values defined at the same index in `_criterias` array
     */
    function setGasUsageAndMinGasPerMinute(
        uint256[] calldata _criteria,
        uint32[] calldata _gasUsage,
        uint32[] calldata _minGasPerMinute
    ) external {
        uint256 criteriasLength = _criteria.length;
        if (criteriasLength != _gasUsage.length || criteriasLength != _minGasPerMinute.length) {
            revert ArrayLengthsDoNotMatch();
        }

        for (uint256 i; i < criteriasLength; ) {
            subsidies[msg.sender][_criteria[i]] = Subsidy(0, _gasUsage[i], _minGasPerMinute[i], 0, 0);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Sets subsidy for a given `_bridge` and `_criteria`
     * @param _bridge Address of the bridge to subsidize
     * @param _criteria A value defining a specific bridge call
     * @param _gasPerMinute A value defining a "speed" at which the subsidy will be released
     * @dev reverts if any of these is true: 1) `_gasPerMinute` <= `Subsidy.gasUsage` divided by seconds in a week,
     *                                       2) subsidy funded before and not yet drained: `subsidy.available` > 0,
     *                                       3) subsidy.gasUsage not set: `subsidy.gasUsage` == 0,
     *                                       4) ETH value sent too low: `msg.value` < `MIN_SUBSIDY_VALUE`.
     */
    function subsidize(
        address _bridge,
        uint256 _criteria,
        uint32 _gasPerMinute
    ) external payable {
        if (msg.value < MIN_SUBSIDY_VALUE) {
            revert SubsidyTooLow();
        }

        // Caching subsidy in order to minimize number of SLOADs and SSTOREs
        Subsidy memory sub = subsidies[_bridge][_criteria];

        if (_gasPerMinute < sub.minGasPerMinute) {
            revert GasPerMinuteTooLow();
        }
        if (sub.available > 0) {
            revert AlreadySubsidized();
        }
        if (sub.gasUsage == 0) {
            revert GasUsageNotSet();
        }

        sub.available = uint128(msg.value);
        sub.lastUpdated = uint32(block.timestamp);
        sub.gasPerMinute = uint32(_gasPerMinute);

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
        uint256 gasToCover = (dt * sub.gasPerMinute) / 1 minutes;
        // At maximum `sub.gasUsage` gets covered
        uint256 ethToCover = (gasToCover < sub.gasUsage ? gasToCover : sub.gasUsage) * block.basefee;
        uint256 subsidyAmount = (ethToCover < sub.available ? ethToCover : sub.available);

        sub.available -= uint128(subsidyAmount);
        sub.lastUpdated = uint32(block.timestamp);

        subsidies[msg.sender][_criteria] = sub;

        // Sending 30k gas in a call to allow receiver to be a multi-sig and write to storage
        (bool success, ) = _beneficiary.call{value: subsidyAmount, gas: 30000}("");
        if (!success) {
            // We don't revert here in order to not allow adversarial rollup provider to cause the bridge to revert
            // --> the bridge call would not succeed and provider would still get a fee
            return 0;
        }

        return subsidyAmount;
    }
}
