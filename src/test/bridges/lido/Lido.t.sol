// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";

import {ICurvePool} from "../../../interfaces/curve/ICurvePool.sol";
import {ILido} from "../../../interfaces/lido/ILido.sol";
import {IWstETH} from "../../../interfaces/lido/IWstETH.sol";

import {LidoBridge} from "../../../bridges/lido/LidoBridge.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

contract LidoTest is BridgeTestBase {
    // solhint-disable-next-line
    ILido public constant LIDO = ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWstETH public constant WRAPPED_STETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ICurvePool public constant CURVE_POOL = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);
    uint256 private constant DUST = 1;

    AztecTypes.AztecAsset private ethAsset;
    AztecTypes.AztecAsset private wstETHAsset;

    LidoBridge private bridge;
    uint256 private idIn;
    uint256 private idOut;

    function setUp() public {
        bridge = new LidoBridge(address(ROLLUP_PROCESSOR), address(ROLLUP_PROCESSOR));
        vm.deal(address(bridge), 0);
        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 500000);
        idIn = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 500000);
        idOut = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        ethAsset = getRealAztecAsset(address(0));
        wstETHAsset = getRealAztecAsset(address(WRAPPED_STETH));

        // Prefund to save gas
        deal(address(WRAPPED_STETH), address(ROLLUP_PROCESSOR), WRAPPED_STETH.balanceOf(address(ROLLUP_PROCESSOR)) + 1);
        deal(address(WRAPPED_STETH), address(bridge), 1);
        LIDO.submit{value: 10}(address(0));
        LIDO.transfer(address(bridge), 10);
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

    function testLidoBridge() public {
        validateLidoBridge(100e18, 50e18);
        validateLidoBridge(50000e18, 40000e18);
    }

    function testDepositLidoAllFixed() public {
        testLidoDepositAll(39429182028115016715909199428625);
    }

    function testLidoDepositAll(uint128 _depositAmount) public {
        uint256 depositAmount = bound(_depositAmount, 1000, 10000 ether);
        validateLidoBridge(depositAmount, depositAmount);
    }

    function testLidoDepositPartial(uint128 _balance) public {
        uint256 balance = bound(_balance, 1000, 10000 ether);
        validateLidoBridge(balance, balance / 2);
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

    /**
        Testing flow:
        1. Send ETH to bridge
        2. Get back wstETH
        3. Send wstETH to bridge
        4. Get back ETH
     */
    function validateLidoBridge(uint256 _balance, uint256 _depositAmount) public {
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

        uint256 wstEthIncrease = _computeEthToWST(_depositAmount);

        uint256 bridgeCallData = encodeBridgeCallData(idIn, ethAsset, emptyAsset, wstETHAsset, emptyAsset, 0);
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(bridgeCallData, getNextNonce(), _depositAmount, wstEthIncrease, 0, true, "");
        sendDefiRollup(bridgeCallData, _depositAmount);

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

        uint256 expectedEth = _computeWSTHToEth(_depositAmount);

        uint256 bridgeCallData = encodeBridgeCallData(idOut, wstETHAsset, emptyAsset, ethAsset, emptyAsset, 0);
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(bridgeCallData, getNextNonce(), _depositAmount, expectedEth, 0, true, "");
        sendDefiRollup(bridgeCallData, _depositAmount);

        assertEq(address(ROLLUP_PROCESSOR).balance, beforeETHBalance + expectedEth, "ETH balance not maching");
        assertEq(
            WRAPPED_STETH.balanceOf(address(ROLLUP_PROCESSOR)),
            beforeWstEthBalance - _depositAmount,
            "WST ETH balance not matching"
        );
        assertGt(WRAPPED_STETH.balanceOf(address(bridge)), 0, "No WST eth in bridge");
        assertGt(WRAPPED_STETH.balanceOf(address(ROLLUP_PROCESSOR)), 0, "No WST eth in rollup");
    }

    function _computeEthToWST(uint256 _amount) internal returns (uint256) {
        uint256 totalShares = LIDO.getTotalShares();
        uint256 totalSupply = LIDO.totalSupply();

        // Compute the number of minted shares and increase internal accounting
        uint256 mintShares = (_amount * totalShares) / totalSupply;
        totalShares += mintShares;
        totalSupply += _amount;

        // Compute the stEth balance of the bridge
        uint256 bridgeShares = LIDO.sharesOf(address(bridge)) + mintShares;
        uint256 stEthBal = (bridgeShares * totalSupply) / totalShares;

        // Compute the amount of wrapped token
        uint256 wstEth = ((stEthBal - DUST) * totalShares) / totalSupply - DUST;

        return wstEth;
    }

    function _computeWSTHToEth(uint256 _amount) internal view returns (uint256) {
        uint256 stETH = LIDO.getPooledEthByShares(_amount);
        uint256 dy = CURVE_POOL.get_dy(1, 0, stETH);
        return dy + address(bridge).balance;
    }
}
