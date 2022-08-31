// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {ExampleBridgeContract} from "../../bridges/example/ExampleBridge.sol";

contract ExampleDeployment is BaseDeployment {
    function deploy() public returns (address) {
        emit log("Deploying example bridge");

        vm.broadcast();
        ExampleBridgeContract bridge = new ExampleBridgeContract(ROLLUP_PROCESSOR);

        emit log_named_address("Example bridge deployed to", address(bridge));

        return address(bridge);
    }

    function deployAndList() public {
        address bridge = deploy();
        uint256 addressId = listBridge(bridge, 250000);
        emit log_named_uint("Example bridge address id", addressId);
    }
}
