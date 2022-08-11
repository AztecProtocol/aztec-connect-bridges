// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {ISubsidy} from "./interfaces/ISubsidy.sol";

/**
 * @title Subsidy
 * @notice A contract which allows anyone to subsidize a bridge
 * @author Jan Benes
 * @dev The goal of this contract is to allow anyone to subsidize a bridge. How the subsidy works is that when a bridge
 *      is subsidized it can call `claimSubsidy(...)` method and in that method the corresponding subsidy amount
 *      unlocks and can be claimed by the beneficiary. Beneficiary is expected to be the beneficiary address passed as
 *      part of the rollup data by the provider. When sufficient subsidy is present it makes it profitable for
 *      the rollup provider to execute a bridge call even when only a small amounts of user fees can be extracted. This
 *      effectively makes it possible for calls to low-use bridges to be included in a rollup block. Without subsidy,
 *      it might happen that the UX of these bridges would dramatically deteriorate since user might wait for a long
 *      time before her/his bridge call gets processed.
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
 *      Since we want to allow a subsidizer to subsidize specific bridge calls/interactions and not only all
 *      calls/interactions we use a `criteria` to distinguish different calls. The `criteria` value is computed in
 *      the bridge, and may use the inputs to `convert(...)`. It is expected to be different in different bridges
 *      (e.g. Uniswap bridge might compute this value based on `_inputAssetA`, `_outputAssetA` and a path defined in
 *      `_auxData`).
 */
contract Subsidy is ISubsidy {
    error ArrayLengthsDoNotMatch();
    error GasPerMinuteTooLow();
    error AlreadySubsidized();
    error GasUsageNotSet();
    error NotSubsidised();
    error SubsidyTooLow();
    error EthTransferFailed();

    event Subsidized(address indexed bridge, uint256 indexed criteria, uint128 available, uint32 gasPerMinute);
    event BeneficiaryRegistered(address indexed beneficiary);

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

    /**
     * @notice Container for Beneficiary related information
     * @member claimable The amount of eth that is owed this beneficiary
     * @member registered A flag indicating if registered or not. Used to "poke" storage
     */
    struct Beneficiary {
        uint248 claimable;
        bool registered;
    }

    // @dev Using min possible `msg.value` upon subsidizing in order to limit possibility of front running attacks
    // --> e.g. attacker front-running real subsidy tx by sending 1 wei value tx making the real one revert
    uint256 public constant MIN_SUBSIDY_VALUE = 1e17;

    // address bridge => uint256 criteria => Subsidy subsidy
    mapping(address => mapping(uint256 => Subsidy)) public subsidies;

    // address beneficiaryAddress => Beneficiary beneficiary
    mapping(address => Beneficiary) public beneficiaries;

    /**
     * @notice Fetch the claimable amount for a specific beneficiary
     * @param _beneficiary The address of the beneficiary to query
     * @return The amount of claimable ETH for `_beneficiary`
     */
    function claimableAmount(address _beneficiary) external view override(ISubsidy) returns (uint256) {
        return beneficiaries[_beneficiary].claimable;
    }

    /**
     * @notice Is the `_beneficiary` registered or not
     * @param _beneficiary The address of the beneficiary to check
     * @return True if the `_beneficiary` is registered, false otherwise
     */
    function isRegistered(address _beneficiary) external view returns (bool) {
        return beneficiaries[_beneficiary].registered;
    }

    /**
     * @notice Get the data related to a specific subsidy
     * @param _bridge The address of the bridge getting the subsidy
     * @param _criteria The criteria of the subsidy
     * @return The subsidy data object
     */
    function getSubsidy(address _bridge, uint256 _criteria) external view returns (Subsidy memory) {
        return subsidies[_bridge][_criteria];
    }

    /**
     * @notice Sets multiple `Subsidy.gasUsage` values for multiple criteria values
     * @dev This function has to be called from the bridge
     * @param _criteria An array of values each defining a specific bridge call
     * @param _gasUsage An array of gas usage for subsidized bridge calls.
     *                  at the same index in `_criteria` array
     * @param _minGasPerMinute An array of minimum amounts of gas per minute that subsidizer has to subsidize for
     *                         the provided criteria.
     */
    function setGasUsageAndMinGasPerMinute(
        uint256[] calldata _criteria,
        uint32[] calldata _gasUsage,
        uint32[] calldata _minGasPerMinute
    ) external override(ISubsidy) {
        uint256 criteriasLength = _criteria.length;
        if (criteriasLength != _gasUsage.length || criteriasLength != _minGasPerMinute.length) {
            revert ArrayLengthsDoNotMatch();
        }

        for (uint256 i; i < criteriasLength; ) {
            setGasUsageAndMinGasPerMinute(_criteria[i], _gasUsage[i], _minGasPerMinute[i]);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Registers address of a beneficiary to receive subsidies
     * @param _beneficiary Address which is going to receive the subsidy
     * @dev This registration is necessary in order to have near constant gas costs in the `claimSubsidy(...)` function.
     *      By writing to the storage slot we make sure that the storage slot is set and later on we pay
     *      a reliable gas cost when updating it. This is important because it's desirable for the cost of
     *      IDefiBridge.convert(...) function to be as predictable as possible. If the cost is too variable users would
     *      overpay since RollupProcessor works with constant gas limits.
     */
    function registerBeneficiary(address _beneficiary) external override(ISubsidy) {
        beneficiaries[_beneficiary].registered = true;
        emit BeneficiaryRegistered(_beneficiary);
    }

    /**
     * @notice Sets subsidy for a given `_bridge` and `_criteria`
     * @param _bridge Address of the bridge to subsidize
     * @param _criteria A value defining the specific bridge call to subsidize
     * @param _gasPerMinute A value defining the "rate" at which the subsidy will be released
     * @dev Reverts if any of these is true: 1) `_gasPerMinute` <= `sub.minGasPerMinute`,
     *                                       2) subsidy funded before and not yet claimed: `subsidy.available` > 0,
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

        sub.available = uint128(msg.value); // safe as an overflow would require more assets than exists.
        sub.lastUpdated = uint32(block.timestamp);
        sub.gasPerMinute = _gasPerMinute;

        subsidies[_bridge][_criteria] = sub;

        emit Subsidized(_bridge, _criteria, sub.available, sub.gasPerMinute);
    }

    /**
     * @notice Tops up an existing subsidy corresponding to a given `_bridge` and `_criteria` with `msg.value`
     * @param _bridge Address of the bridge to subsidize
     * @param _criteria A value defining the specific bridge call to subsidize
     * @dev Reverts if `available` is 0.
     */
    function topUp(address _bridge, uint256 _criteria) external payable {
        // Caching subsidy in order to minimize number of SLOADs and SSTOREs
        Subsidy memory sub = subsidies[_bridge][_criteria];

        if (sub.available == 0) {
            revert NotSubsidised();
        }

        unchecked {
            sub.available += uint128(msg.value);
        }
        subsidies[_bridge][_criteria] = sub;

        emit Subsidized(_bridge, _criteria, sub.available, sub.gasPerMinute);
    }

    /**
     * @notice Computes and sends subsidy
     * @param _criteria A value defining a specific bridge call
     * @param _beneficiary Address which is going to receive the subsidy
     * @return subsidy ETH amount which was added to the `_beneficiary` claimable balance
     */
    function claimSubsidy(uint256 _criteria, address _beneficiary) external returns (uint256) {
        if (_beneficiary == address(0)) {
            return 0;
        }

        Beneficiary memory beneficiary = beneficiaries[_beneficiary];
        if (!beneficiary.registered) {
            return 0;
        }

        // Caching subsidy in order to minimize number of SLOADs and SSTOREs
        Subsidy memory sub = subsidies[msg.sender][_criteria];
        if (sub.available == 0) {
            return 0;
        }

        uint256 subsidyAmount;

        unchecked {
            uint256 dt = block.timestamp - sub.lastUpdated; // sub.lastUpdated only update to block.timestamp, so can never be in the future

            // time need to have passed for an incentive to have accrued
            if (dt > 0) {
                // The following should never overflow due to constraints on values. But if they do, it is bounded by the available subsidy
                uint256 gasToCover = (dt * sub.gasPerMinute) / 1 minutes;
                uint256 ethToCover = (gasToCover < sub.gasUsage ? gasToCover : sub.gasUsage) * block.basefee; // At maximum `sub.gasUsage` gas covered

                subsidyAmount = ethToCover < sub.available ? ethToCover : sub.available;

                sub.available -= uint128(subsidyAmount); // safe as `subsidyAmount` is bounded by `sub.available`
                sub.lastUpdated = uint32(block.timestamp);

                // Update storage
                beneficiaries[_beneficiary].claimable = beneficiary.claimable + uint248(subsidyAmount); // safe as available is limited to u128
                subsidies[msg.sender][_criteria] = sub;
            }
        }

        return subsidyAmount;
    }

    /**
     * @notice Withdraws beneficiary's withdrawable balance
     * @dev Beware that this can be called by anyone to force a payout to the beneficiary.
     *      Done like this to support smart-contract beneficiaries that can handle eth, but not make the call itself.
     * @param _beneficiary Address which is going to receive the subsidy
     * @return - ETH amount which was sent to the `_beneficiary`
     */
    function withdraw(address _beneficiary) external returns (uint256) {
        uint256 withdrawableBalance = beneficiaries[_beneficiary].claimable;
        // Immediately updating the balance to avoid re-entrancy attack
        beneficiaries[_beneficiary].claimable = 0;

        // Sending 30k gas in a call to allow receiver to be a multi-sig and write to storage
        /* solhint-disable avoid-low-level-calls */
        (bool success, ) = _beneficiary.call{value: withdrawableBalance, gas: 30000}("");
        if (!success) {
            revert EthTransferFailed();
        }
        return withdrawableBalance;
    }

    /**
     * @notice Sets `Subsidy.gasUsage` value for a given criteria
     * @dev This function has to be called from the bridge
     * @param _criteria A value defining a specific bridge call
     * @param _gasUsage The gas usage of the subsidized action. Used as upper limit for subsidy.
     * @param _minGasPerMinute Minimum amount of gas per minute that subsidizer has to subsidize
     */
    function setGasUsageAndMinGasPerMinute(
        uint256 _criteria,
        uint32 _gasUsage,
        uint32 _minGasPerMinute
    ) public override(ISubsidy) {
        // Loading `sub` first in order to not overwrite `sub.available` in case this function was already called
        // before and subsidy was set. This should not be needed for well written bridges.
        Subsidy memory sub = subsidies[msg.sender][_criteria];

        sub.gasUsage = _gasUsage;
        sub.minGasPerMinute = _minGasPerMinute;

        subsidies[msg.sender][_criteria] = sub;
    }
}
