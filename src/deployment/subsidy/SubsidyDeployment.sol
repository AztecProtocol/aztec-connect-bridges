// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {Subsidy} from "../../aztec/Subsidy.sol";

contract SubsidyDeployment is BaseDeployment {
    function deploy() public returns (address) {
        emit log("Deploying Subsidy contract");

        vm.broadcast();
        Subsidy subsidy = new Subsidy();
        emit log_named_address("Subsidy contract deployed to ", address(subsidy));

        return address(subsidy);
    }
}
