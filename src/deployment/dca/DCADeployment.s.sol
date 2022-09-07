// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {UniswapDCABridge} from "../../bridges/dca/UniswapDCABridge.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract DCADeployment is BaseDeployment {
    uint256 internal constant TICK_SIZE = 1 days;
    uint256 internal constant FEE = 10; // 10 bps

    function deploy() public returns (address) {
        emit log("Deploying Uniswap DCA bridge");

        vm.broadcast();
        UniswapDCABridge bridge = new UniswapDCABridge(ROLLUP_PROCESSOR, TICK_SIZE, FEE);

        emit log_named_address("Uniswap DCA bridge deployed to", address(bridge));

        assertEq(bridge.ASSET_A().allowance(address(bridge), ROLLUP_PROCESSOR), type(uint256).max);
        assertEq(bridge.ASSET_B().allowance(address(bridge), ROLLUP_PROCESSOR), type(uint256).max);

        return address(bridge);
    }

    function deployAndList() public returns (address) {
        address bridge = deploy();

        uint256 addressId = listBridge(bridge, 400000);
        emit log_named_uint("Uniswap DCA bridge address id", addressId);

        return bridge;
    }
}
