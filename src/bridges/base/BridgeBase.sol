// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IDefiBridge} from "../../aztec/interfaces/IDefiBridge.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "./ErrorLib.sol";

/**
 * @title BridgeBase
 * @notice A base that bridges can be built upon which imports a limited set of features
 * @dev Reverts `convert` with missing implementation, and `finalise` with async disabled
 * @author Lasse Herskind
 */
abstract contract BridgeBase is IDefiBridge {
    error MissingImplementation();

    address public immutable ROLLUP_PROCESSOR;

    constructor(address _rollupProcessor) {
        ROLLUP_PROCESSOR = _rollupProcessor;
    }

    modifier onlyRollup() {
        if (msg.sender != ROLLUP_PROCESSOR) {
            revert ErrorLib.InvalidCaller();
        }
        _;
    }

    function convert(
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        uint256,
        uint256,
        uint64,
        address
    )
        external
        payable
        virtual
        override(IDefiBridge)
        returns (
            uint256,
            uint256,
            bool
        )
    {
        revert MissingImplementation();
    }

    function finalise(
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        uint256,
        uint64
    )
        external
        payable
        virtual
        override(IDefiBridge)
        returns (
            uint256,
            uint256,
            bool
        )
    {
        revert ErrorLib.AsyncDisabled();
    }

    /**
     * @notice Computes the criteria that is passed on to the subsidy contract when claiming
     * @dev Should be overridden by bridge implementation if intended to limit subsidy.
     * @return The criteria to be passed along
     */
    function computeCriteria(
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        uint64
    ) public view virtual returns (uint256) {
        return 0;
    }
}
