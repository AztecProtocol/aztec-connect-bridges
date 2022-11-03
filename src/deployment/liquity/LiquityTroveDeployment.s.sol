// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {TroveBridge} from "../../bridges/liquity/TroveBridge.sol";

contract LiquityTroveDeployment is BaseDeployment {
    function deploy(uint256 _initialCr) public returns (address) {
        emit log("Deploying example bridge");

        vm.broadcast();
        TroveBridge bridge = new TroveBridge(ROLLUP_PROCESSOR, _initialCr);

        emit log_named_address("Example bridge deployed to", address(bridge));

        return address(bridge);
    }

    function deployAndList(uint256 _initialCr) public {
        address bridge = deploy(_initialCr);
        uint256 addressId = listBridge(bridge, 1000000);
        emit log_named_uint("Example bridge address id", addressId);

        listAsset(TroveBridge(payable(bridge)).LUSD(), 55000);
    }
}
