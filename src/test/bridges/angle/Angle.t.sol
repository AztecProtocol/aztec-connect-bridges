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

    function setUp() public {
        emit log_named_uint("block number", block.number);
        bridge = new AngleBridge(address(ROLLUP_PROCESSOR));
        vm.label(address(bridge), "ANGLE_BRIDGE");
        vm.deal(address(bridge), 0);

        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 5000000);
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        daiAsset = getRealAztecAsset(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
        ethAsset = getRealAztecAsset(address(0));
        wethAsset = AztecTypes.AztecAsset({
            id: 123,
            erc20Address: address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        unsupportedAsset = AztecTypes.AztecAsset({
            id: 456,
            erc20Address: address(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        sanDaiAsset = AztecTypes.AztecAsset({
            id: 789,
            erc20Address: address(0x7B8E89b0cE7BAC2cfEC92A371Da899eA8CBdb450),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
    }

    function testWrongInputOutputAssets() public {
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));

        vm.startPrank(address(ROLLUP_PROCESSOR));

        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));

        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(unsupportedAsset, emptyAsset, unsupportedAsset, emptyAsset, 0, 0, 0, address(0));

        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(ethAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));

        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(daiAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));

        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(daiAsset, emptyAsset, daiAsset, emptyAsset, 0, 0, 0, address(0));

        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(sanDaiAsset, emptyAsset, daiAsset, emptyAsset, 0, 0, 0, address(0));

        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(sanDaiAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 1, address(0));

        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(daiAsset, emptyAsset, sanDaiAsset, emptyAsset, 0, 0, 1, address(0));

        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(daiAsset, emptyAsset, daiAsset, emptyAsset, 0, 0, 1, address(0));

        vm.stopPrank();
    }

    function testZeroDeposit() public {
        vm.startPrank(address(ROLLUP_PROCESSOR));
        (uint256 outputValueA, , ) = bridge.convert(daiAsset, emptyAsset, sanDaiAsset, emptyAsset, 0, 0, 0, address(0));
        assertEq(outputValueA, 0);
        vm.stopPrank();
    }

    function testValidDeposit() public {
        vm.startPrank(address(ROLLUP_PROCESSOR));

        deal(daiAsset.erc20Address, address(bridge), 1 ether);
        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(
            0xc9daabC677F3d1301006e723bD21C60be57a5915
        );
        (uint256 outputValueA, , ) = bridge.convert(
            daiAsset,
            emptyAsset,
            sanDaiAsset,
            emptyAsset,
            1 ether,
            0,
            0,
            address(0)
        );
        assertEq(IERC20(daiAsset.erc20Address).balanceOf(address(bridge)), 0);
        assertEq(IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge)), outputValueA);
        assertEq(outputValueA, (1 ether * 1e18) / sanRate);

        vm.stopPrank();
    }

    function testMultipleDeposits() public {
        vm.startPrank(address(ROLLUP_PROCESSOR));

        uint256 totalOutput = 0;

        deal(daiAsset.erc20Address, address(bridge), 1 ether);
        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(
            0xc9daabC677F3d1301006e723bD21C60be57a5915
        );
        (uint256 outputValueA, , ) = bridge.convert(
            daiAsset,
            emptyAsset,
            sanDaiAsset,
            emptyAsset,
            1 ether,
            0,
            0,
            address(0)
        );
        totalOutput += outputValueA;

        assertEq(IERC20(daiAsset.erc20Address).balanceOf(address(bridge)), 0);
        assertEq(IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge)), totalOutput);
        assertEq(outputValueA, (1 ether * 1e18) / sanRate);

        deal(daiAsset.erc20Address, address(bridge), 2 ether);
        (, , , , , sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(0xc9daabC677F3d1301006e723bD21C60be57a5915);
        (outputValueA, , ) = bridge.convert(daiAsset, emptyAsset, sanDaiAsset, emptyAsset, 2 ether, 0, 0, address(0));
        totalOutput += outputValueA;
        assertEq(IERC20(daiAsset.erc20Address).balanceOf(address(bridge)), 0);
        assertEq(IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge)), totalOutput);
        assertEq(outputValueA, (2 ether * 1e18) / sanRate);

        vm.stopPrank();
    }

    function testZeroWithdraw() public {
        vm.startPrank(address(ROLLUP_PROCESSOR));

        (uint256 outputValueA, , ) = bridge.convert(sanDaiAsset, emptyAsset, daiAsset, emptyAsset, 0, 0, 1, address(0));
        assertEq(outputValueA, 0);

        vm.stopPrank();
    }

    function testValidWithdraw() public {
        vm.startPrank(address(ROLLUP_PROCESSOR));

        deal(sanDaiAsset.erc20Address, address(bridge), 1 ether);
        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(
            0xc9daabC677F3d1301006e723bD21C60be57a5915
        );
        (uint256 outputValueA, , ) = bridge.convert(
            sanDaiAsset,
            emptyAsset,
            daiAsset,
            emptyAsset,
            1 ether,
            0,
            1,
            address(0)
        );
        assertEq(IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge)), 0);
        assertEq(IERC20(daiAsset.erc20Address).balanceOf(address(bridge)), outputValueA);
        assertEq(outputValueA, sanRate);

        vm.stopPrank();
    }

    function testMultipleWithdraws() public {
        vm.startPrank(address(ROLLUP_PROCESSOR));

        uint256 totalOutput = 0;

        deal(sanDaiAsset.erc20Address, address(bridge), 1 ether);
        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(
            0xc9daabC677F3d1301006e723bD21C60be57a5915
        );
        (uint256 outputValueA, , ) = bridge.convert(
            sanDaiAsset,
            emptyAsset,
            daiAsset,
            emptyAsset,
            1 ether,
            0,
            1,
            address(0)
        );
        totalOutput += outputValueA;
        assertEq(IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge)), 0);
        assertEq(IERC20(daiAsset.erc20Address).balanceOf(address(bridge)), totalOutput);
        assertEq(outputValueA, sanRate);

        deal(sanDaiAsset.erc20Address, address(bridge), 2 ether);
        (, , , , , sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(0xc9daabC677F3d1301006e723bD21C60be57a5915);
        (outputValueA, , ) = bridge.convert(sanDaiAsset, emptyAsset, daiAsset, emptyAsset, 2 ether, 0, 1, address(0));
        totalOutput += outputValueA;
        assertEq(IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge)), 0);
        assertEq(IERC20(daiAsset.erc20Address).balanceOf(address(bridge)), totalOutput);
        assertEq(outputValueA, 2 * sanRate);

        vm.stopPrank();
    }
}
