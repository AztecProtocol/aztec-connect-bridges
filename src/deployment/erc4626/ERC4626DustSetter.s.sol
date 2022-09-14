// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {ERC4626Bridge} from "../../bridges/erc4626/ERC4626Bridge.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract ERC4626DustSetter is BaseDeployment {
    IERC4626 private constant VAULT = IERC4626(0x60897720AA966452e8706e74296B018990aEc527); // ERC4626-Wrapped Euler wstETH
    address private constant BRIDGE = 0x3578D6D5e1B4F07A48bb1c958CBfEc135bef7d98;

    function depositToVaultAndSendDustToBridge() public {
        address asset = VAULT.asset();
        vm.startBroadcast();
        IERC20(asset).approve(address(VAULT), type(uint256).max);
        VAULT.mint(1, BRIDGE);
        vm.stopBroadcast();

        emit log_named_uint("Share balance of bridge", VAULT.balanceOf(BRIDGE));
    }
}
