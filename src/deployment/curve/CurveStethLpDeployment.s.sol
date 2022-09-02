// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {CurveStEthBridge} from "../../bridges/curve/CurveStEthBridge.sol";
import {ILido} from "../../interfaces/lido/ILido.sol";
import {IWstETH} from "../../interfaces/lido/IWstETH.sol";
import {Deployer} from "../../bridges/curve/Deployer.sol";
import {ICurvePool} from "../../interfaces/curve/ICurvePool.sol";

interface ICurveStEthLpBridge {
    function CURVE_POOL() external view returns (address);

    function get_lp_token() external view returns (address);
}

interface ICurveStEthPool {
    function add_liquidity(uint256[2] memory _amounts, uint256 min_mint_amount) external payable returns (uint256);
}

contract CurveStethLpDeployment is BaseDeployment {
    ILido internal constant STETH = ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWstETH internal constant WSTETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    address internal constant CURVE_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    function fundWithDust(address _bridge) public {
        ICurveStEthLpBridge bridge = ICurveStEthLpBridge(_bridge);
        IERC20 lpToken = IERC20(bridge.get_lp_token());

        vm.label(address(STETH), "STETH");
        vm.label(address(WSTETH), "WSTETH");

        uint256[2] memory amounts;
        amounts[0] = 1000;

        vm.startBroadcast();
        STETH.submit{value: 1000}(address(0));
        STETH.transfer(_bridge, 10);

        STETH.approve(address(WSTETH), 1000);
        WSTETH.wrap(50);
        WSTETH.transfer(_bridge, 10);
        WSTETH.transfer(ROLLUP_PROCESSOR, 10);

        ICurveStEthPool(CURVE_POOL).add_liquidity{value: amounts[0]}(amounts, 0);
        lpToken.transfer(ROLLUP_PROCESSOR, 10);
        lpToken.transfer(_bridge, 10);

        vm.stopBroadcast();

        assertGt(STETH.balanceOf(_bridge), 0, "no steth");
        assertGt(WSTETH.balanceOf(_bridge), 0, "no wsteth");
    }

    function deploy() public returns (address) {
        emit log("Deploying curve steth lp bridge");

        vm.broadcast();
        Deployer deployer = new Deployer();

        string[] memory cmds = new string[](2);
        cmds[0] = "vyper";
        cmds[1] = "src/bridges/curve/CurveStEthLpBridge.vy";
        bytes memory code = vm.ffi(cmds);

        bytes memory bytecode = abi.encodePacked(code, abi.encode(ROLLUP_PROCESSOR));

        vm.broadcast();
        address bridgeAddress = deployer.deploy(bytecode);
        ICurveStEthLpBridge bridge = ICurveStEthLpBridge(bridgeAddress);

        emit log_named_address("Curve LP bridge deployed to", address(bridge));

        emit log_named_address("Lp token", bridge.get_lp_token());

        assertEq(WSTETH.allowance(address(bridge), ROLLUP_PROCESSOR), type(uint256).max);
        assertEq(STETH.allowance(address(bridge), address(WSTETH)), type(uint256).max);
        assertEq(STETH.allowance(address(bridge), CURVE_POOL), type(uint256).max);
        assertEq(IERC20(bridge.get_lp_token()).allowance(address(bridge), ROLLUP_PROCESSOR), type(uint256).max);

        return bridgeAddress;
    }

    function deployAndFund() public returns (address) {
        address bridge = deploy();
        fundWithDust(bridge);
        return bridge;
    }

    function deployAndList() public returns (address) {
        address bridge = deployAndFund();
        ICurveStEthLpBridge bridge_ = ICurveStEthLpBridge(bridge);

        uint256 addressId = listBridge(bridge, 250000);
        emit log_named_uint("Curve bridge address id", addressId);

        listAsset(bridge_.get_lp_token(), 100000);

        return bridge;
    }
}
