// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {TroveBridge} from "../../bridges/liquity/TroveBridge.sol";

contract LiquityTroveDeployment is BaseDeployment {
    uint256 internal constant INITIAL_CR = 30; // TODO: update

    function setUp() public virtual {
        NETWORK = Network.DEVNET;
        MODE = Mode.BROADCAST;
        configure();
    }

    function deploy() public returns (address) {
        emit log("Deploying example bridge");

        vm.broadcast();
        TroveBridge bridge = new TroveBridge(ROLLUP_PROCESSOR, INITIAL_CR);

        emit log_named_address("Example bridge deployed to", address(bridge));

        return address(bridge);
    }

    function deployAndList() public {
        address bridge = deploy();
        uint256 addressId = listBridge(bridge, 250000);
        emit log_named_uint("Example bridge address id", addressId);
    }
}
