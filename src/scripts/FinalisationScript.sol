// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";

interface IMulticall {
    struct Call {
        address target;
        bytes callData;
    }

    function aggregate(Call[] memory _calls) external returns (uint256 blockNumber, bytes[] memory returnData);
}

contract FinalisationScript is Test {
    IMulticall private constant MULTI_CALL = IMulticall(0xeefBa1e63905eF1D7ACbA5a8513c70307C1cE441);
    address private constant ROLLUP_PROCESSOR = 0xFF1F2B4ADb9dF6FC8eAFecDcbF96A2B351680455;

    // TODO: update the array with actual nonces
    uint256[] private interactionNonces = [100, 101, 102];

    function testFinaliseAll() public {
        IMulticall.Call[] memory calls = new IMulticall.Call[](interactionNonces.length);
        for (uint256 i = 0; i < interactionNonces.length; i++) {
            bytes memory callData =
                abi.encodeWithSignature("processAsyncDefiInteraction(uint256)", interactionNonces[i]);
            calls[i] = IMulticall.Call(ROLLUP_PROCESSOR, callData);
        }
        MULTI_CALL.aggregate(calls);
    }
}
