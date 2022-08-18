// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {CompoundBridge} from "../../bridges/compound/CompoundBridge.sol";

contract CompoundDeployment is BaseDeployment {
    // solhint-disable-next-line
    address internal constant cETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    // solhint-disable-next-line
    address internal constant cDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;

    function deploy() public returns (address) {
        emit log("Deploying Compound bridge");

        vm.broadcast();
        CompoundBridge bridge = new CompoundBridge(ROLLUP_PROCESSOR);
        emit log_named_address("Compound bridge deployed to", address(bridge));

        vm.broadcast();
        bridge.preApprove(cETH);

        vm.broadcast();
        bridge.preApprove(cDAI);

        return address(bridge);
    }

    function deployAndList() public {
        address bridge = deploy();
        uint256 addressId = listBridge(bridge, 500000);

        listAsset(cETH, 100000);
        listAsset(cDAI, 100000);

        emit log_named_uint("Compound bridge address id", addressId);
    }
}
