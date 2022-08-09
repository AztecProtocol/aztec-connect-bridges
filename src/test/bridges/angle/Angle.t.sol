// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICERC20} from "../../../interfaces/compound/ICERC20.sol";
import {AngleBridge} from "../../../bridges/angle/AngleBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

contract AngleTest is BridgeTestBase {
    using SafeERC20 for IERC20;

    AztecTypes.AztecAsset private daiAsset;
    AztecTypes.AztecAsset private ethAsset;
    AztecTypes.AztecAsset private wethAsset;
    AztecTypes.AztecAsset private unsupportedAsset;

    AztecTypes.AztecAsset private sanDaiAsset;

    AngleBridge internal bridge;
    uint256 internal id;

    uint256 internal constant DUST = 1;

    function setUp() public {
        emit log_named_uint("block number", block.number);
        bridge = new AngleBridge(address(ROLLUP_PROCESSOR));
        vm.label(address(bridge), "ANGLE_BRIDGE");
        vm.deal(address(bridge), 0);

        vm.startPrank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 200000);
        ROLLUP_PROCESSOR.setSupportedAsset(0x7B8E89b0cE7BAC2cfEC92A371Da899eA8CBdb450, 100000);
        ROLLUP_PROCESSOR.setSupportedAsset(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 100000);
        vm.stopPrank();

        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        daiAsset = getRealAztecAsset(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        ethAsset = getRealAztecAsset(address(0));
        wethAsset = getRealAztecAsset(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        sanDaiAsset = getRealAztecAsset(0x7B8E89b0cE7BAC2cfEC92A371Da899eA8CBdb450);

        unsupportedAsset = AztecTypes.AztecAsset({
            id: 456,
            erc20Address: 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        deal(daiAsset.erc20Address, address(bridge), DUST);
        deal(sanDaiAsset.erc20Address, address(bridge), DUST);
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

    function testValidDeposit() public {
        vm.startPrank(address(ROLLUP_PROCESSOR));

        uint256 amount = 1 ether;

        uint256 balance = IERC20(daiAsset.erc20Address).balanceOf(address(bridge));
        deal(daiAsset.erc20Address, address(bridge), amount + balance);

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
        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(
            0xc9daabC677F3d1301006e723bD21C60be57a5915
        );
        assertEq(outputValueA, (amount * 1e18) / sanRate);

        vm.stopPrank();
    }

    function testMultipleDeposits(uint96 _amount) public {
        vm.assume(_amount > 10);
        vm.startPrank(address(ROLLUP_PROCESSOR));

        uint256 balance = IERC20(daiAsset.erc20Address).balanceOf(address(bridge));
        deal(daiAsset.erc20Address, address(bridge), _amount + balance);

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
        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(
            0xc9daabC677F3d1301006e723bD21C60be57a5915
        );
        assertEq(outputValueA, (uint256(_amount) * 1e18) / sanRate);

        uint256 input2 = 3 * uint256(_amount);
        balance = IERC20(daiAsset.erc20Address).balanceOf(address(bridge));

        deal(daiAsset.erc20Address, address(bridge), input2 + balance);
        deal(sanDaiAsset.erc20Address, address(bridge), DUST); // reset sanDAI balance

        (outputValueA, , ) = bridge.convert(daiAsset, emptyAsset, sanDaiAsset, emptyAsset, input2, 0, 0, address(0));
        assertEq(IERC20(daiAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge)), outputValueA + DUST);
        (, , , , , sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(0xc9daabC677F3d1301006e723bD21C60be57a5915);
        assertEq(outputValueA, (input2 * 1e18) / sanRate);

        vm.stopPrank();
    }

    function testValidWithdraw() public {
        vm.startPrank(address(ROLLUP_PROCESSOR));

        uint256 amount = 1 ether;
        uint256 balance = IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge));
        deal(sanDaiAsset.erc20Address, address(bridge), amount + balance);

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
        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(
            0xc9daabC677F3d1301006e723bD21C60be57a5915
        );
        assertEq(outputValueA, (amount * sanRate) / 1e18);

        vm.stopPrank();
    }

    function testMultipleWithdraws(uint96 _amount) public {
        // the protocol might not have so many sanDAI available, so we limit what can be withdrawn
        uint256 amount = uint256(bound(_amount, 10, 50000 ether));

        vm.startPrank(address(ROLLUP_PROCESSOR));

        uint256 balance = IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge));
        deal(sanDaiAsset.erc20Address, address(bridge), amount + balance);

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
        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(
            0xc9daabC677F3d1301006e723bD21C60be57a5915
        );
        assertEq(outputValueA, (amount * sanRate) / 1e18);

        uint256 input2 = 5 * amount;

        balance = IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge));
        deal(sanDaiAsset.erc20Address, address(bridge), input2 + balance);
        deal(daiAsset.erc20Address, address(bridge), DUST); // reset DAI balance

        (outputValueA, , ) = bridge.convert(sanDaiAsset, emptyAsset, daiAsset, emptyAsset, input2, 0, 1, address(0));
        assertEq(IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(IERC20(daiAsset.erc20Address).balanceOf(address(bridge)), outputValueA + DUST);
        (, , , , , sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(0xc9daabC677F3d1301006e723bD21C60be57a5915);
        assertEq(outputValueA, (input2 * sanRate) / 1e18);

        vm.stopPrank();
    }

    function testValidDepositE2E(uint96 _amount) public {
        uint256 balanceRollupBeforeDAI = IERC20(daiAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 amount = uint256(_amount);
        amount = bound(amount, 10, balanceRollupBeforeDAI - 1);

        uint256 balanceRollupBeforeSanDAI = IERC20(sanDaiAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));

        uint256 bridgeCallData = encodeBridgeCallData(id, daiAsset, emptyAsset, sanDaiAsset, emptyAsset, 0);
        (uint256 outputValueA, , ) = sendDefiRollup(bridgeCallData, amount);

        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(
            0xc9daabC677F3d1301006e723bD21C60be57a5915
        );

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

        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(
            0xc9daabC677F3d1301006e723bD21C60be57a5915
        );

        assertEq(outputValueA, (amount * sanRate) / 1e18);
        assertEq(IERC20(daiAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge)), DUST);

        uint256 balanceRollupAfterDAI = IERC20(daiAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 balanceRollupAfterSanDAI = IERC20(sanDaiAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));

        assertEq(balanceRollupAfterDAI, balanceRollupBeforeDAI + outputValueA);
        assertEq(balanceRollupAfterSanDAI, balanceRollupBeforeSanDAI - amount);
    }
}
