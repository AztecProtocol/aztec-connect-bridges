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
        uint256 addressId = listBridge(bridge, 170000);
        emit log_named_uint("Angle SLP deposit bridge address id", addressId);
        addressId = listBridge(bridge, 200000);
        emit log_named_uint("Angle SLP withdraw bridge address id", addressId);

        // Listing just the san tokens whose underlying are currently listed
        // TODO: change the following gas limits
        listAsset(AngleSLPBridge(bridge).SANDAI(), 100000);
        listAsset(AngleSLPBridge(bridge).SANWETH(), 100000);

        return bridge;
    }
}
