// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {ExampleBridgeContract} from "../../bridges/example/ExampleBridge.sol";
import {Subsidy} from "../../aztec/Subsidy.sol";
import {ISubsidy} from "../../aztec/interfaces/ISubsidy.sol";

contract ExampleDeployment is BaseDeployment {

    function setUp() public virtual {
        NETWORK = Network.DEVNET;
        MODE = Mode.BROADCAST;
        configure();
    }

    function deploy() public returns (address) {
        emit log("Deploying example bridge");

        vm.broadcast();
        Subsidy sub = new Subsidy();

        vm.broadcast();
        ExampleBridgeContract bridge = new ExampleBridgeContract(ROLLUP_PROCESSOR, sub);

        emit log_named_address("Example bridge deployed to", address(bridge));

        return address(bridge);
    }

    function deployAndList() public {
        address bridge = deploy();

        listBridge(bridge, 250000);

        uint256 addressId = bridgesLength();
        emit log_named_uint("Example bridge address id", addressId);
    }
}
