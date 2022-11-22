// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";

import {ICurvePool} from "../../../interfaces/curve/ICurvePool.sol";
import {ILido} from "../../../interfaces/lido/ILido.sol";
import {IWstETH} from "../../../interfaces/lido/IWstETH.sol";

import {CurveStEthBridge} from "../../../bridges/curve/CurveStEthBridge.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

contract CurveStEthBridgeTest is BridgeTestBase {
    // solhint-disable-next-line
    ILido public constant LIDO = ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWstETH public constant WRAPPED_STETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ICurvePool public constant CURVE_POOL = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    AztecTypes.AztecAsset private ethAsset;
    AztecTypes.AztecAsset private wstETHAsset;

    CurveStEthBridge private bridge;
    uint256 private id;

    function setUp() public {
        bridge = new CurveStEthBridge(address(ROLLUP_PROCESSOR));

        vm.deal(address(bridge), 0);
        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 175000);
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        ethAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        wstETHAsset = ROLLUP_ENCODER.getRealAztecAsset(address(WRAPPED_STETH));

        // Prefund to save gas
        deal(address(WRAPPED_STETH), address(ROLLUP_PROCESSOR), WRAPPED_STETH.balanceOf(address(ROLLUP_PROCESSOR)) + 1);
        deal(address(WRAPPED_STETH), address(bridge), 1);
        LIDO.submit{value: 10}(address(0));
        LIDO.transfer(address(bridge), 10);

        vm.label(address(bridge.LIDO()), "LIDO");
        vm.label(address(bridge.WRAPPED_STETH()), "WRAPPED_STETH");
        vm.label(address(bridge.CURVE_POOL()), "CURVE_POOL");
    }

    function testErrorCodes() public {
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));

        vm.startPrank(address(ROLLUP_PROCESSOR));

        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));

        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(ethAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));

        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(wstETHAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));

        vm.expectRevert(ErrorLib.AsyncDisabled.selector);
        bridge.finalise(wstETHAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0);

        vm.stopPrank();
    }

    function testCurveBridge() public {
        validateCurveBridge(100e18, 50e18);
        validateCurveBridge(50000e18, 40000e18);
    }

    function testDepositCurveAllFixed() public {
        testCurveDepositAll(39429182028115016715909199428625);
    }

    function testCurveDepositAll(uint128 _depositAmount) public {
        uint256 depositAmount = bound(_depositAmount, 1000, 10000 ether);
        validateCurveBridge(depositAmount, depositAmount);
    }

    function testCurveDepositPartial(uint128 _balance) public {
        uint256 balance = bound(_balance, 1000, 10000 ether);
        validateCurveBridge(balance, balance / 2);
    }

    function testMultipleDeposits(uint80 _a, uint80 _b) public {
        uint256 a = bound(_a, 1000, 10000 ether);
        uint256 b = bound(_b, 1000, 10000 ether);

        vm.deal(address(ROLLUP_PROCESSOR), uint256(a) + b);

        // Convert ETH to wstETH
        validateWrap(a);
        validateWrap(b);
    }

    function testDepositThenPartialWithdraw(uint80 _a) public {
        uint256 a = bound(_a, 1000, 10000 ether);
        vm.deal(address(ROLLUP_PROCESSOR), a);

        validateWrap(a);

        validateUnwrap(WRAPPED_STETH.balanceOf(address(ROLLUP_PROCESSOR)) / 2);
    }

    function testMinPriceTooBigWrap() public {
        uint256 depositAmount = 1e18;
        vm.deal(address(bridge), depositAmount);

        uint256 expectedPrice = CURVE_POOL.get_dy(0, 1, depositAmount);
        uint64 minPrice = uint64((expectedPrice * 101) / 100); // Min price is 1% larger than what we should receive

        vm.prank(address(ROLLUP_PROCESSOR));
        vm.expectRevert("Exchange resulted in fewer coins than expected");
        bridge.convert(ethAsset, emptyAsset, wstETHAsset, emptyAsset, depositAmount, 0, minPrice, address(0));
    }

    function testMinPriceTooBigUnwrap() public {
        uint256 depositAmount = 1e18;
        deal(address(WRAPPED_STETH), address(bridge), depositAmount);

        uint256 expectedPrice = CURVE_POOL.get_dy(1, 0, depositAmount);
        uint64 minPrice = uint64((expectedPrice * 101) / 100); // Min price is 1% larger than what we should receive

        vm.prank(address(ROLLUP_PROCESSOR));
        vm.expectRevert("Exchange resulted in fewer coins than expected");
        bridge.convert(wstETHAsset, emptyAsset, ethAsset, emptyAsset, depositAmount, 0, minPrice, address(0));
    }

    /**
     * Testing flow:
     *     1. Send ETH to bridge
     *     2. Get back wstETH
     *     3. Send wstETH to bridge
     *     4. Get back ETH
     */
    function validateCurveBridge(uint256 _balance, uint256 _depositAmount) public {
        // Send ETH to bridge
        vm.deal(address(ROLLUP_PROCESSOR), _balance);

        // Convert ETH to wstETH
        validateWrap(_depositAmount);

        // convert wstETH back to ETH using the same bridge
        validateUnwrap(WRAPPED_STETH.balanceOf(address(ROLLUP_PROCESSOR)) - 1);
    }

    function validateWrap(uint256 _depositAmount) public {
        uint256 beforeETHBalance = address(ROLLUP_PROCESSOR).balance;
        uint256 beforeWstETHBalance = WRAPPED_STETH.balanceOf(address(ROLLUP_PROCESSOR));

        uint256 expectedStEth = CURVE_POOL.get_dy(0, 1, _depositAmount);
        uint64 minPrice = uint64((expectedStEth * bridge.PRECISION()) / _depositAmount);

        uint256 wstEthIncrease = _computeEthToWST(_depositAmount);

        uint256 bridgeCallData = ROLLUP_ENCODER.defiInteractionL2(
            id, ethAsset, emptyAsset, wstETHAsset, emptyAsset, minPrice, _depositAmount
        );

        ROLLUP_ENCODER.registerEventToBeChecked(
            bridgeCallData, ROLLUP_ENCODER.getNextNonce(), _depositAmount, wstEthIncrease, 0, true, ""
        );
        ROLLUP_ENCODER.processRollup();

        assertEq(address(ROLLUP_PROCESSOR).balance, beforeETHBalance - _depositAmount, "ETH balance not matching");
        assertEq(
            WRAPPED_STETH.balanceOf(address(ROLLUP_PROCESSOR)),
            beforeWstETHBalance + wstEthIncrease,
            "WST ETH balance not matching"
        );
        assertGt(WRAPPED_STETH.balanceOf(address(bridge)), 0, "No WST eth in bridge");
        assertGt(WRAPPED_STETH.balanceOf(address(ROLLUP_PROCESSOR)), 0, "No WST eth in rollup");
    }

    function validateUnwrap(uint256 _depositAmount) public {
        uint256 beforeETHBalance = address(ROLLUP_PROCESSOR).balance;
        uint256 beforeWstEthBalance = WRAPPED_STETH.balanceOf(address(ROLLUP_PROCESSOR));

        uint256 unwrappedStStEth = LIDO.getPooledEthByShares(_depositAmount);
        uint64 minPrice = uint64((CURVE_POOL.get_dy(1, 0, unwrappedStStEth) * bridge.PRECISION()) / unwrappedStStEth);

        uint256 expectedEth = _computeWSTHToEth(_depositAmount);

        uint256 bridgeCallData = ROLLUP_ENCODER.defiInteractionL2(
            id, wstETHAsset, emptyAsset, ethAsset, emptyAsset, minPrice, _depositAmount
        );

        ROLLUP_ENCODER.registerEventToBeChecked(
            bridgeCallData, ROLLUP_ENCODER.getNextNonce(), _depositAmount, expectedEth, 0, true, ""
        );
        ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        assertEq(address(ROLLUP_PROCESSOR).balance, beforeETHBalance + expectedEth, "ETH balance not matching");
        assertEq(
            WRAPPED_STETH.balanceOf(address(ROLLUP_PROCESSOR)),
            beforeWstEthBalance - _depositAmount,
            "WST ETH balance not matching"
        );
        assertGt(WRAPPED_STETH.balanceOf(address(bridge)), 0, "No WST eth in bridge");
        assertGt(WRAPPED_STETH.balanceOf(address(ROLLUP_PROCESSOR)), 0, "No WST eth in rollup");
    }

    function _computeEthToWST(uint256 _amount) internal view returns (uint256) {
        uint256 stEthBal = CURVE_POOL.get_dy(0, 1, _amount);
        uint256 wstEth = LIDO.getSharesByPooledEth(stEthBal);
        return wstEth;
    }

    function _computeWSTHToEth(uint256 _amount) internal view returns (uint256) {
        uint256 stETH = LIDO.getPooledEthByShares(_amount);
        uint256 dy = CURVE_POOL.get_dy(1, 0, stETH);
        return dy + address(bridge).balance;
    }
}
