// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {DonationBridge} from "../../bridges/donation/DonationBridge.sol";

contract DonationDeployment is BaseDeployment {
    function setUp() public virtual {
        NETWORK = Network.DEVNET;
        MODE = Mode.BROADCAST;
        configure();
    }

    function deploy() public returns (address) {
        emit log("Deploying Donation bridge");

        vm.broadcast();
        DonationBridge bridge = new DonationBridge(ROLLUP_PROCESSOR);
        emit log_named_address("Donation bridge deployed to", address(bridge));

        return address(bridge);
    }

    function deployAndList() public {
        address bridge = deploy();
        uint256 addressId = listBridge(bridge, 5000);
        emit log_named_uint("Donation bridge address id", addressId);
    }
}
