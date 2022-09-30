// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {AngleSLPBridge} from "../../bridges/angle/AngleSLPBridge.sol";

contract AngleSLPDeployment is BaseDeployment {
    function deploy() public returns (address payable) {
        emit log("Deploying Angle SLP bridge");

        vm.broadcast();
        AngleSLPBridge bridge = new AngleSLPBridge(ROLLUP_PROCESSOR);
        emit log_named_address("Angle SLP bridge deployed to", address(bridge));

        return payable(address(bridge));
    }

    function deployAndList() public returns (address) {
        address payable bridge = deploy();
        uint256 addressId = listBridge(bridge, 250000);
        emit log_named_uint("Angle SLP deposit bridge address id", addressId);
        addressId = listBridge(bridge, 1500000);
        emit log_named_uint("Angle SLP withdraw bridge address id", addressId);

        // Listing just the san tokens whose underlying are currently listed
        listAsset(AngleSLPBridge(bridge).SANDAI(), 55000);
        listAsset(AngleSLPBridge(bridge).SANWETH(), 55000);

        return bridge;
    }
}
