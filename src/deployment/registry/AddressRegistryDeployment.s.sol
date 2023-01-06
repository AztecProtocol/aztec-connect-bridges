// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {AddressRegistry} from "../../bridges/registry/AddressRegistry.sol";

contract AddressRegistryDeployment is BaseDeployment {
    function deploy() public returns (address) {
        emit log("Deploying AddressRegistry bridge");

        vm.broadcast();
        AddressRegistry bridge = new AddressRegistry(ROLLUP_PROCESSOR);

        emit log_named_address("AddressRegistry bridge deployed to", address(bridge));

        return address(bridge);
    }

    function deployAndList() public returns (address) {
        address bridge = deploy();

        uint256 addressId = listBridge(bridge, 120500);
        emit log_named_uint("AddressRegistry bridge address id", addressId);

        return bridge;
    }
}
