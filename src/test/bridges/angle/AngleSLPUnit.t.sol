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

contract AngleSLPUnitTest is BridgeTestBase {
    using SafeERC20 for IERC20;

    AztecTypes.AztecAsset private daiAsset;
    AztecTypes.AztecAsset private usdcAsset;
    AztecTypes.AztecAsset private ethAsset;
    AztecTypes.AztecAsset private unsupportedAsset;

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
        usdcAsset = getRealAztecAsset(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        ethAsset = getRealAztecAsset(address(0));
        sanDaiAsset = getRealAztecAsset(0x7B8E89b0cE7BAC2cfEC92A371Da899eA8CBdb450);
        sanUsdcAsset = getRealAztecAsset(0x9C215206Da4bf108aE5aEEf9dA7caD3352A36Dad);
        unsupportedAsset = AztecTypes.AztecAsset({
            id: 456,
            erc20Address: 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        deal(daiAsset.erc20Address, address(bridge), DUST);
        deal(sanDaiAsset.erc20Address, address(bridge), DUST);
        deal(usdcAsset.erc20Address, address(bridge), DUST);
        deal(sanUsdcAsset.erc20Address, address(bridge), DUST);
    }

    function testWrongInputOutputAssets() public {
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 10, 0, 0, address(0));

        vm.startPrank(address(ROLLUP_PROCESSOR));

        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 10, 0, 0, address(0));

        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(unsupportedAsset, emptyAsset, unsupportedAsset, emptyAsset, 10, 0, 0, address(0));

        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(ethAsset, emptyAsset, emptyAsset, emptyAsset, 10, 0, 0, address(0));

        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(daiAsset, emptyAsset, emptyAsset, emptyAsset, 10, 0, 0, address(0));

        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(daiAsset, emptyAsset, daiAsset, emptyAsset, 10, 0, 0, address(0));

        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(sanDaiAsset, emptyAsset, daiAsset, emptyAsset, 10, 0, 0, address(0));

        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(sanDaiAsset, emptyAsset, emptyAsset, emptyAsset, 10, 0, 1, address(0));

        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(daiAsset, emptyAsset, sanDaiAsset, emptyAsset, 10, 0, 1, address(0));

        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(daiAsset, emptyAsset, daiAsset, emptyAsset, 10, 0, 1, address(0));

        vm.expectRevert(ErrorLib.InvalidInputAmount.selector);
        bridge.convert(daiAsset, emptyAsset, sanDaiAsset, emptyAsset, 0, 0, 0, address(0));

        vm.expectRevert(ErrorLib.InvalidInputAmount.selector);
        bridge.convert(daiAsset, emptyAsset, sanDaiAsset, emptyAsset, 0, 0, 1, address(0));

        vm.stopPrank();
    }

    function testValidDeposit(uint96 _amount) public {
        vm.assume(_amount > 10);
        uint256 amount = uint256(_amount);

        uint256 balance = IERC20(daiAsset.erc20Address).balanceOf(address(bridge));
        deal(daiAsset.erc20Address, address(bridge), amount + balance);

        vm.prank(address(ROLLUP_PROCESSOR));
        (uint256 outputValueA, , ) = bridge.convert(
            daiAsset,
            emptyAsset,
            sanDaiAsset,
            emptyAsset,
            amount,
            0,
            0,
            address(0)
        );

        assertEq(IERC20(daiAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge)), outputValueA + DUST);
        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(bridge.POOLMANAGER_DAI());
        assertEq(outputValueA, (amount * 1e18) / sanRate);
    }

    function testMultipleDeposits(uint96 _amount) public {
        vm.assume(_amount > 10);

        uint256 balance = IERC20(daiAsset.erc20Address).balanceOf(address(bridge));
        deal(daiAsset.erc20Address, address(bridge), _amount + balance);

        vm.prank(address(ROLLUP_PROCESSOR));
        (uint256 outputValueA, , ) = bridge.convert(
            daiAsset,
            emptyAsset,
            sanDaiAsset,
            emptyAsset,
            uint256(_amount),
            0,
            0,
            address(0)
        );

        assertEq(IERC20(daiAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge)), outputValueA + DUST);
        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(bridge.POOLMANAGER_DAI());
        assertEq(outputValueA, (uint256(_amount) * 1e18) / sanRate);

        uint256 input2 = 3 * uint256(_amount);
        balance = IERC20(daiAsset.erc20Address).balanceOf(address(bridge));

        deal(daiAsset.erc20Address, address(bridge), input2 + balance);
        deal(sanDaiAsset.erc20Address, address(bridge), DUST); // reset sanDAI balance

        vm.prank(address(ROLLUP_PROCESSOR));
        (outputValueA, , ) = bridge.convert(daiAsset, emptyAsset, sanDaiAsset, emptyAsset, input2, 0, 0, address(0));
        assertEq(IERC20(daiAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge)), outputValueA + DUST);
        (, , , , , sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(bridge.POOLMANAGER_DAI());
        assertEq(outputValueA, (input2 * 1e18) / sanRate);
    }

    function testValidWithdraw(uint96 _amount) public {
        // the protocol might not have so many sanDAI available, so we limit what can be withdrawn
        uint256 amount = uint256(bound(_amount, 10, 50000 ether));

        uint256 balance = IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge));
        deal(sanDaiAsset.erc20Address, address(bridge), amount + balance);

        vm.prank(address(ROLLUP_PROCESSOR));
        (uint256 outputValueA, , ) = bridge.convert(
            sanDaiAsset,
            emptyAsset,
            daiAsset,
            emptyAsset,
            amount,
            0,
            1,
            address(0)
        );
        assertEq(IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(IERC20(daiAsset.erc20Address).balanceOf(address(bridge)), outputValueA + DUST);
        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(bridge.POOLMANAGER_DAI());
        assertEq(outputValueA, (amount * sanRate) / 1e18);
    }

    function testMultipleWithdraws(uint96 _amount) public {
        // the protocol might not have so many sanDAI available, so we limit what can be withdrawn
        uint256 amount = uint256(bound(_amount, 10, 50000 ether));

        uint256 balance = IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge));
        deal(sanDaiAsset.erc20Address, address(bridge), amount + balance);

        vm.prank(address(ROLLUP_PROCESSOR));
        (uint256 outputValueA, , ) = bridge.convert(
            sanDaiAsset,
            emptyAsset,
            daiAsset,
            emptyAsset,
            amount,
            0,
            1,
            address(0)
        );
        assertEq(IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(IERC20(daiAsset.erc20Address).balanceOf(address(bridge)), outputValueA + DUST);
        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(bridge.POOLMANAGER_DAI());
        assertEq(outputValueA, (amount * sanRate) / 1e18);

        uint256 input2 = 5 * amount;

        balance = IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge));
        deal(sanDaiAsset.erc20Address, address(bridge), input2 + balance);
        deal(daiAsset.erc20Address, address(bridge), DUST); // reset DAI balance

        vm.prank(address(ROLLUP_PROCESSOR));
        (outputValueA, , ) = bridge.convert(sanDaiAsset, emptyAsset, daiAsset, emptyAsset, input2, 0, 1, address(0));
        assertEq(IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(IERC20(daiAsset.erc20Address).balanceOf(address(bridge)), outputValueA + DUST);
        (, , , , , sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(bridge.POOLMANAGER_DAI());
        assertEq(outputValueA, (input2 * sanRate) / 1e18);
    }

    function testDepositUSDC(uint96 _amount) public {
        vm.assume(_amount > 10);
        uint256 amount = uint256(_amount);

        uint256 balance = IERC20(usdcAsset.erc20Address).balanceOf(address(bridge));
        deal(usdcAsset.erc20Address, address(bridge), amount + balance);

        vm.prank(address(ROLLUP_PROCESSOR));
        (uint256 outputValueA, , ) = bridge.convert(
            usdcAsset,
            emptyAsset,
            sanUsdcAsset,
            emptyAsset,
            amount,
            0,
            0,
            address(0)
        );

        assertEq(IERC20(usdcAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(IERC20(sanUsdcAsset.erc20Address).balanceOf(address(bridge)), outputValueA + DUST);
        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(bridge.POOLMANAGER_USDC());
        assertEq(outputValueA, (amount * 1e18) / sanRate);
    }

    function testWithdrawUSDC(uint96 _amount) public {
        // the protocol might not have so many sanUSDC available, so we limit what can be withdrawn
        uint256 amount = uint256(bound(_amount, 10, 50000e6));

        uint256 balance = IERC20(sanUsdcAsset.erc20Address).balanceOf(address(bridge));
        deal(sanUsdcAsset.erc20Address, address(bridge), amount + balance);

        vm.prank(address(ROLLUP_PROCESSOR));
        (uint256 outputValueA, , ) = bridge.convert(
            sanUsdcAsset,
            emptyAsset,
            usdcAsset,
            emptyAsset,
            amount,
            0,
            1,
            address(0)
        );
        assertEq(IERC20(sanUsdcAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(IERC20(usdcAsset.erc20Address).balanceOf(address(bridge)), outputValueA + DUST);
        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(bridge.POOLMANAGER_USDC());
        assertEq(outputValueA, (amount * sanRate) / 1e18);
    }
}
