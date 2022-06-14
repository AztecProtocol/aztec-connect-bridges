// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {IDefiBridge} from "../../interfaces/IDefiBridge.sol";
import {AztecTypes} from "../../aztec/AztecTypes.sol";
import {ErrorLib} from "./ErrorLib.sol";

/**
 * @title BridgeBase
 * @notice A base that bridges can be built upon which imports a limited set of features
 * @dev Reverts `convert` with missing implementation, and `finalise` with async disabled
 * @author Lasse Herskind
 */
contract BridgeBase is IDefiBridge {
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
}
