// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {ERC4626Bridge} from "../../bridges/erc4626/ERC4626Bridge.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract ERC4626Deployment is BaseDeployment {
    function deploy() public returns (address) {
        emit log("Deploying ERC4626 bridge");

        vm.broadcast();
        ERC4626Bridge bridge = new ERC4626Bridge(ROLLUP_PROCESSOR);
        emit log_named_address("ERC4626 bridge deployed to", address(bridge));

        return address(bridge);
    }

    function deployAndList() public returns (address) {
        address bridge = deploy();

        uint256 depositAddressId = listBridge(bridge, 300000);
        emit log_named_uint("ERC4626 bridge address id", depositAddressId);

        return bridge;
    }
}
