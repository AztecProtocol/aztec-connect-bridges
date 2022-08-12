// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICERC20} from "../../../interfaces/compound/ICERC20.sol";
import {AngleSLPBridge} from "../../../bridges/angle/AngleSLPBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

contract AngleSLPE2ETest is BridgeTestBase {
    using SafeERC20 for IERC20;

    AztecTypes.AztecAsset private daiAsset;
    AztecTypes.AztecAsset private usdcAsset;

    AztecTypes.AztecAsset private sanDaiAsset;
    AztecTypes.AztecAsset private sanUsdcAsset;

    AngleSLPBridge internal bridge;
    uint256 internal id;

    uint256 internal constant DUST = 1;

    function setUp() public {
        emit log_named_uint("block number", block.number);
        bridge = new AngleSLPBridge(address(ROLLUP_PROCESSOR));
        vm.label(address(bridge), "ANGLE_BRIDGE");
        vm.deal(address(bridge), 0);

        vm.startPrank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 200000);
        ROLLUP_PROCESSOR.setSupportedAsset(0x7B8E89b0cE7BAC2cfEC92A371Da899eA8CBdb450, 100000); // sanDAI
        ROLLUP_PROCESSOR.setSupportedAsset(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 100000); // USDC
        ROLLUP_PROCESSOR.setSupportedAsset(0x9C215206Da4bf108aE5aEEf9dA7caD3352A36Dad, 100000); // sanUSDC
        vm.stopPrank();

        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        daiAsset = getRealAztecAsset(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        sanDaiAsset = getRealAztecAsset(0x7B8E89b0cE7BAC2cfEC92A371Da899eA8CBdb450);

        usdcAsset = getRealAztecAsset(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        sanUsdcAsset = getRealAztecAsset(0x9C215206Da4bf108aE5aEEf9dA7caD3352A36Dad);

        deal(daiAsset.erc20Address, address(bridge), DUST);
        deal(sanDaiAsset.erc20Address, address(bridge), DUST);
        deal(usdcAsset.erc20Address, address(bridge), DUST);
        deal(sanUsdcAsset.erc20Address, address(bridge), DUST);

        // since the rollup doesn't have USDC, we deal some to it
        deal(usdcAsset.erc20Address, address(ROLLUP_PROCESSOR), 100000e6);
    }

    function testValidDepositE2E(uint96 _amount) public {
        uint256 balanceRollupBeforeDAI = IERC20(daiAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 amount = uint256(_amount);
        amount = bound(amount, 10, balanceRollupBeforeDAI - 1);

        uint256 balanceRollupBeforeSanDAI = IERC20(sanDaiAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));

        uint256 bridgeCallData = encodeBridgeCallData(id, daiAsset, emptyAsset, sanDaiAsset, emptyAsset, 0);
        (uint256 outputValueA, , ) = sendDefiRollup(bridgeCallData, amount);

        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(bridge.POOLMANAGER_DAI());

        assertEq(outputValueA, (amount * 1e18) / sanRate);
        assertEq(IERC20(daiAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge)), DUST);

        uint256 balanceRollupAfterDAI = IERC20(daiAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 balanceRollupAfterSanDAI = IERC20(sanDaiAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));

        assertEq(balanceRollupAfterDAI, balanceRollupBeforeDAI - amount);
        assertEq(balanceRollupAfterSanDAI, balanceRollupBeforeSanDAI + outputValueA);
    }

    function testValidWithdrawE2E(uint96 _amount) public {
        // the protocol might not have so many sanDAI available, so we limit what can be withdrawn
        uint256 amount = uint256(bound(_amount, 10, 100000 ether));

        deal(sanDaiAsset.erc20Address, address(ROLLUP_PROCESSOR), amount);

        uint256 balanceRollupBeforeDAI = IERC20(daiAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 balanceRollupBeforeSanDAI = IERC20(sanDaiAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));

        uint256 bridgeCallData = encodeBridgeCallData(id, sanDaiAsset, emptyAsset, daiAsset, emptyAsset, 1);
        (uint256 outputValueA, , ) = sendDefiRollup(bridgeCallData, amount);

        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(bridge.POOLMANAGER_DAI());

        assertEq(outputValueA, (amount * sanRate) / 1e18);
        assertEq(IERC20(daiAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge)), DUST);

        uint256 balanceRollupAfterDAI = IERC20(daiAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 balanceRollupAfterSanDAI = IERC20(sanDaiAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));

        assertEq(balanceRollupAfterDAI, balanceRollupBeforeDAI + outputValueA);
        assertEq(balanceRollupAfterSanDAI, balanceRollupBeforeSanDAI - amount);
    }

    function testDepositUSDC(uint96 _amount) public {
        uint256 balanceRollupBeforeUSDC = IERC20(usdcAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));

        uint256 amount = uint256(_amount);
        amount = bound(amount, 10, balanceRollupBeforeUSDC - 1);

        uint256 balanceRollupBeforeSanUSDC = IERC20(sanUsdcAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));

        uint256 bridgeCallData = encodeBridgeCallData(id, usdcAsset, emptyAsset, sanUsdcAsset, emptyAsset, 0);
        (uint256 outputValueA, , ) = sendDefiRollup(bridgeCallData, amount);

        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(bridge.POOLMANAGER_USDC());

        assertEq(outputValueA, (amount * 1e18) / sanRate);
        assertEq(IERC20(usdcAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(IERC20(sanUsdcAsset.erc20Address).balanceOf(address(bridge)), DUST);

        uint256 balanceRollupAfterUSDC = IERC20(usdcAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 balanceRollupAfterSanUSDC = IERC20(sanUsdcAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));

        assertEq(balanceRollupAfterUSDC, balanceRollupBeforeUSDC - amount);
        assertEq(balanceRollupAfterSanUSDC, balanceRollupBeforeSanUSDC + outputValueA);
    }

    function testWithdrawUSDC(uint96 _amount) public {
        // the protocol might not have so many sanUSDC available, so we limit what can be withdrawn
        uint256 amount = uint256(bound(_amount, 10, 100000e6));

        deal(sanUsdcAsset.erc20Address, address(ROLLUP_PROCESSOR), amount);

        uint256 balanceRollupBeforeUSDC = IERC20(usdcAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 balanceRollupBeforeSanUSDC = IERC20(sanUsdcAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));

        uint256 bridgeCallData = encodeBridgeCallData(id, sanUsdcAsset, emptyAsset, usdcAsset, emptyAsset, 1);
        (uint256 outputValueA, , ) = sendDefiRollup(bridgeCallData, amount);

        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(bridge.POOLMANAGER_USDC());

        assertEq(outputValueA, (amount * sanRate) / 1e18);
        assertEq(IERC20(usdcAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(IERC20(sanUsdcAsset.erc20Address).balanceOf(address(bridge)), DUST);

        uint256 balanceRollupAfterUSDC = IERC20(usdcAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 balanceRollupAfterSanUSDC = IERC20(sanUsdcAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));

        assertEq(balanceRollupAfterUSDC, balanceRollupBeforeUSDC + outputValueA);
        assertEq(balanceRollupAfterSanUSDC, balanceRollupBeforeSanUSDC - amount);
    }
}
