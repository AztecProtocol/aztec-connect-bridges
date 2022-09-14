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

    function depositToVaultAndSendDustToBridge() public {
        address bridge = 0x3578D6D5e1B4F07A48bb1c958CBfEc135bef7d98;
        address asset = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH
        IERC4626 vault = IERC4626(0x3c66B18F67CA6C1A71F829E2F6a0c987f97462d0); // ERC4626-Wrapped Euler wstETH
        vm.startBroadcast();
        IERC20(asset).approve(address(vault), type(uint256).max);
        vault.mint(1, bridge);
        vm.stopBroadcast();

        emit log_named_uint("Share balance of bridge", vault.balanceOf(bridge));
    }
}
