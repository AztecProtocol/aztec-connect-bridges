// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {CurveStEthBridge} from "../../bridges/curve/CurveStEthBridge.sol";
import {ILido} from "../../interfaces/lido/ILido.sol";
import {IWstETH} from "../../interfaces/lido/IWstETH.sol";

contract CurveDeployment is BaseDeployment {
    function fundWithDust(address _bridge) public {
        CurveStEthBridge bridge = CurveStEthBridge(payable(_bridge));

        ILido steth = bridge.LIDO();
        IWstETH wstETH = bridge.WRAPPED_STETH();

        vm.label(address(steth), "STETH");
        vm.label(address(wstETH), "WSTETH");

        vm.startBroadcast();
        steth.submit{value: 1000}(address(0));
        steth.transfer(address(bridge), 10);

        steth.approve(address(wstETH), 1000);
        wstETH.wrap(50);
        wstETH.transfer(address(bridge), 10);
        wstETH.transfer(ROLLUP_PROCESSOR, 10);

        vm.stopBroadcast();

        assertGt(steth.balanceOf(address(bridge)), 0, "no steth");
        assertGt(wstETH.balanceOf(address(bridge)), 0, "no wsteth");
    }

    function deploy() public returns (address, address) {
        emit log("Deploying curve steth bridge");

        vm.broadcast();
        CurveStEthBridge bridge = new CurveStEthBridge(ROLLUP_PROCESSOR);

        emit log_named_address("Curve bridge deployed to", address(bridge));

        assertEq(bridge.WRAPPED_STETH().allowance(address(bridge), ROLLUP_PROCESSOR), type(uint256).max);
        assertEq(bridge.LIDO().allowance(address(bridge), address(bridge.WRAPPED_STETH())), type(uint256).max);
        assertEq(bridge.LIDO().allowance(address(bridge), address(bridge.CURVE_POOL())), type(uint256).max);

        return (address(bridge), address(bridge.WRAPPED_STETH()));
    }

    function deployAndFund() public returns (address, address) {
        (address bridge, address wstEth) = deploy();
        fundWithDust(bridge);
        return (bridge, wstEth);
    }

    function deployAndList() public {
        (address bridge, address wstEth) = deployAndFund();

        uint256 addressId = listBridge(bridge, 250000);
        emit log_named_uint("Curve bridge address id", addressId);

        listAsset(wstEth, 100000);
    }
}
