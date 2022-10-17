// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {ERC4626Bridge} from "../../bridges/erc4626/ERC4626Bridge.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";

contract ERC4626Lister is BaseDeployment {
    function listVault(address _bridge, address _vault) public {
        ERC4626Bridge bridge = ERC4626Bridge(payable(_bridge));

        IERC4626 vault = IERC4626(_vault);
        IERC20 asset = IERC20(vault.asset());

        if (vault.allowance(address(bridge), ROLLUP_PROCESSOR) == type(uint256).max) {
            return;
        }
        if (asset.allowance(address(bridge), address(vault)) == type(uint256).max) {
            return;
        }

        vm.broadcast();
        bridge.listVault(address(vault));

        emit log_named_string("Listed vault", vault.symbol());
    }
}
