// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";

import {ICurvePool} from "../../../interfaces/curve/ICurvePool.sol";
import {ILido} from "../../../interfaces/lido/ILido.sol";
import {IWstETH} from "../../../interfaces/lido/IWstETH.sol";
import {IDefiBridge} from "../../../aztec/interfaces/IDefiBridge.sol";

import {CurveStEthBridge} from "../../../bridges/curve/CurveStEthBridge.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {VyperDeployer} from "../../../../lib/vyper-deploy/VyperDeployer.sol";

contract CurveLpTest is BridgeTestBase {
    // solhint-disable-next-line
    IERC20 public constant LP_TOKEN = IERC20(0x06325440D014e39736583c165C2963BA99fAf14E);
    ILido public constant LIDO = ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWstETH public constant WRAPPED_STETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ICurvePool public constant CURVE_POOL = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    AztecTypes.AztecAsset private ethAsset;
    AztecTypes.AztecAsset private wstETHAsset;
    AztecTypes.AztecAsset private lpAsset;

    IDefiBridge private bridge;
    uint256 private bridgeAddressId;

    function setUp() public {
        VyperDeployer deployer = new VyperDeployer();
        bytes memory args = abi.encode(address(ROLLUP_PROCESSOR));
        address b = deployer.deployContract("curve/CurveStEthLpBridge", args);

        emit log_named_address("Bridge", b);

        bridge = IDefiBridge(b);

        vm.deal(address(bridge), 0);
        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 500000);
        bridgeAddressId = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        ethAsset = getRealAztecAsset(address(0));
        wstETHAsset = getRealAztecAsset(address(WRAPPED_STETH));

        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedAsset(address(LP_TOKEN), 100000);
        lpAsset = getRealAztecAsset(address(LP_TOKEN));

        // Prefund to save gas
        deal(address(WRAPPED_STETH), address(ROLLUP_PROCESSOR), WRAPPED_STETH.balanceOf(address(ROLLUP_PROCESSOR)) + 1);
        deal(address(WRAPPED_STETH), address(bridge), 1);
        LIDO.submit{value: 10}(address(0));
        LIDO.transfer(address(bridge), 10);
    }

    function testOne() public {
        vm.prank(address(ROLLUP_PROCESSOR));
        bridge.convert{value: 10 ether}(ethAsset, emptyAsset, lpAsset, emptyAsset, 10 ether, 0, 0, address(this));

        deal(address(WRAPPED_STETH), address(bridge), 10 ether);
        vm.prank(address(ROLLUP_PROCESSOR));
        bridge.convert(wstETHAsset, emptyAsset, lpAsset, emptyAsset, 10 ether, 0, 0, address(this));
        emit log_named_uint("Balance", LP_TOKEN.balanceOf(address(bridge)));

        uint256 lpAmount = LP_TOKEN.balanceOf(address(bridge));
       emit log_named_uint("Balance", address(ROLLUP_PROCESSOR).balance);
 
        vm.prank(address(ROLLUP_PROCESSOR));
        bridge.convert(lpAsset, emptyAsset, ethAsset, wstETHAsset, lpAmount / 2, 0, 0, address(this));
        emit log_named_uint("Balance", LP_TOKEN.balanceOf(address(bridge)));
        emit log_named_uint("Balance", WRAPPED_STETH.balanceOf(address(bridge)));
        emit log_named_uint("Balance", address(bridge).balance);
        emit log_named_uint("Balance", address(ROLLUP_PROCESSOR).balance);
    }
}
