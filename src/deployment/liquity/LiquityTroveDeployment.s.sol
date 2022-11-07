// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {TroveBridge} from "../../bridges/liquity/TroveBridge.sol";

contract LiquityTroveDeployment is BaseDeployment {
    function deploy(uint256 _initialCr) public returns (address) {
        emit log("Deploying trove bridge");

        vm.broadcast();
        TroveBridge bridge = new TroveBridge(ROLLUP_PROCESSOR, _initialCr);

        emit log_named_address("Trove bridge deployed to", address(bridge));

        return address(bridge);
    }

    function deployAndList(uint256 _initialCr) public {
        address bridge = deploy(_initialCr);
        uint256 addressId = listBridge(bridge, 550_000);
        emit log_named_uint("Trove bridge address id", addressId);

        listAsset(TroveBridge(payable(bridge)).LUSD(), 55_000);
        listAsset(bridge, 55_000);
    }
}
