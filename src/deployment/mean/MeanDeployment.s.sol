// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IDCAHub} from "../../interfaces/mean/IDCAHub.sol";
import {ITransformerRegistry} from "../../interfaces/mean/ITransformerRegistry.sol";
import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {MeanBridge} from "../../bridges/mean/MeanBridge.sol";

contract ERC4626Deployment is BaseDeployment {


    IDCAHub private constant HUB = IDCAHub(0xA5AdC5484f9997fBF7D405b9AA62A7d88883C345);
    ITransformerRegistry private constant TRANSFORMER_REGISTRY = ITransformerRegistry(0xC0136591Df365611B1452B5F8823dEF69Ff3A685);
    address private constant OWNER = 0xEC864BE26084ba3bbF3cAAcF8F6961A9263319C4;

    function deploy() public returns (address) {
        emit log("Deploying Mean bridge");

        vm.broadcast();
        MeanBridge bridge = new MeanBridge(HUB, TRANSFORMER_REGISTRY, OWNER, ROLLUP_PROCESSOR);
        emit log_named_address("Mean bridge deployed to", address(bridge));

        return address(bridge);
    }
}
