// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test, Vm} from "forge-std/Test.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {IRollupProcessorV2} from "rollup-encoder/interfaces/IRollupProcessorV2.sol";
import {ISubsidy} from "../../../aztec/interfaces/ISubsidy.sol";
import {RollupEncoder} from "rollup-encoder/RollupEncoder.sol";

/**
 * @notice Helper contract that allow us to test bridges against the live rollup by sending mock rollups with defi interactions
 *         The helper will setup the state and impersonate parties to allow easy interaction with the rollup
 * @author Lasse Herskind
 */
abstract contract BridgeTestBase is Test {
    IRollupProcessorV2 internal constant ROLLUP_PROCESSOR =
        IRollupProcessorV2(0xFF1F2B4ADb9dF6FC8eAFecDcbF96A2B351680455);
    ISubsidy internal constant SUBSIDY = ISubsidy(0xABc30E831B5Cc173A9Ed5941714A7845c909e7fA);
    address internal constant MULTI_SIG = 0xE298a76986336686CC3566469e3520d23D1a8aaD;

    RollupEncoder internal immutable ROLLUP_ENCODER;

    AztecTypes.AztecAsset internal emptyAsset;

    constructor() {
        ROLLUP_ENCODER = new RollupEncoder(address(ROLLUP_PROCESSOR));
    }
}
