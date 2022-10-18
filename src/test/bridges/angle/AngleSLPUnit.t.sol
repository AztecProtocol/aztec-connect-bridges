// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AngleSLPBridge} from "../../../bridges/angle/AngleSLPBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

contract AngleSLPUnitTest is BridgeTestBase {
    using SafeERC20 for IERC20;

    AztecTypes.AztecAsset private daiAsset;
    AztecTypes.AztecAsset private usdcAsset;
    AztecTypes.AztecAsset private ethAsset;
    AztecTypes.AztecAsset private wethAsset;
    AztecTypes.AztecAsset private unsupportedAsset;

    AztecTypes.AztecAsset private sanDaiAsset;
    AztecTypes.AztecAsset private sanUsdcAsset;
    AztecTypes.AztecAsset private sanWethAsset;

    AngleSLPBridge internal bridge;
    uint256 internal id;

    uint256 internal constant DUST = 1;

    function setUp() public {
        emit log_named_uint("block number", block.number);
        bridge = new AngleSLPBridge(address(ROLLUP_PROCESSOR));
        vm.label(address(bridge), "ANGLE_BRIDGE");
        vm.deal(address(bridge), 0);

        vm.startPrank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 1500000);
        ROLLUP_PROCESSOR.setSupportedAsset(0x7B8E89b0cE7BAC2cfEC92A371Da899eA8CBdb450, 55000); // sanDAI
        ROLLUP_PROCESSOR.setSupportedAsset(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 55000); // USDC
        ROLLUP_PROCESSOR.setSupportedAsset(0x9C215206Da4bf108aE5aEEf9dA7caD3352A36Dad, 55000); // sanUSDC
        ROLLUP_PROCESSOR.setSupportedAsset(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 55000); // WETH
        ROLLUP_PROCESSOR.setSupportedAsset(0x30c955906735e48D73080fD20CB488518A6333C8, 55000); // sanWETH
        vm.stopPrank();

        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        daiAsset = ROLLUP_ENCODER.getRealAztecAssetset(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        usdcAsset = ROLLUP_ENCODER.getRealAztecAssetset(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        ethAsset = ROLLUP_ENCODER.getRealAztecAssetset(address(0));
        wethAsset = ROLLUP_ENCODER.getRealAztecAssetset(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        sanWethAsset = ROLLUP_ENCODER.getRealAztecAssetset(0x30c955906735e48D73080fD20CB488518A6333C8);
        sanDaiAsset = ROLLUP_ENCODER.getRealAztecAssetset(0x7B8E89b0cE7BAC2cfEC92A371Da899eA8CBdb450);
        sanUsdcAsset = ROLLUP_ENCODER.getRealAztecAssetset(0x9C215206Da4bf108aE5aEEf9dA7caD3352A36Dad);
        unsupportedAsset = AztecTypes.AztecAsset({
            id: 456,
            erc20Address: 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        deal(daiAsset.erc20Address, address(bridge), DUST);
        deal(sanDaiAsset.erc20Address, address(bridge), DUST);
        deal(usdcAsset.erc20Address, address(bridge), DUST);
        deal(sanUsdcAsset.erc20Address, address(bridge), DUST);
        deal(wethAsset.erc20Address, address(bridge), DUST);
        deal(sanWethAsset.erc20Address, address(bridge), DUST);
    }

    function testWrongInputOutputAssets() public {
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 10, 0, 0, address(0));

        vm.startPrank(address(ROLLUP_PROCESSOR));

        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 10, 0, 0, address(0));

        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(unsupportedAsset, emptyAsset, unsupportedAsset, emptyAsset, 10, 0, 0, address(0));

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

        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(sanWethAsset, emptyAsset, ethAsset, emptyAsset, 10, 0, 0, address(0));

        vm.expectRevert();
        bridge.convert(ethAsset, emptyAsset, sanWethAsset, emptyAsset, 100, 0, 1, address(0));

        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(wethAsset, emptyAsset, ethAsset, emptyAsset, 100, 0, 0, address(0));

        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(wethAsset, emptyAsset, ethAsset, emptyAsset, 100, 0, 1, address(0));

        uint256 amount = 10000;
        deal(daiAsset.erc20Address, address(bridge), amount);
        vm.expectRevert(ErrorLib.InvalidAuxData.selector);
        bridge.convert(daiAsset, emptyAsset, sanDaiAsset, emptyAsset, amount, 0, 2, address(0));

        vm.expectRevert(ErrorLib.InvalidAuxData.selector);
        bridge.convert(daiAsset, emptyAsset, sanDaiAsset, emptyAsset, amount, 0, 5, address(0));

        vm.stopPrank();
    }

    function testEthDeposits() public {
        uint256 amount = 1 ether;
        deal(wethAsset.erc20Address, address(bridge), amount);
        vm.deal(address(bridge), amount);

        vm.startPrank(address(ROLLUP_PROCESSOR));

        bridge.convert(wethAsset, emptyAsset, sanWethAsset, emptyAsset, 10000, 0, 0, address(0));
        bridge.convert(ethAsset, emptyAsset, sanWethAsset, emptyAsset, 10000, 0, 0, address(0));

        vm.stopPrank();
    }

    function testEthWithdraws() public {
        uint256 amount = 1 ether;

        deal(wethAsset.erc20Address, address(bridge), 0);
        vm.deal(address(bridge), 0);
        deal(sanWethAsset.erc20Address, address(bridge), amount);

        vm.startPrank(address(ROLLUP_PROCESSOR));

        bridge.convert(sanWethAsset, emptyAsset, wethAsset, emptyAsset, 1000, 0, 1, address(0));
        bridge.convert(sanWethAsset, emptyAsset, ethAsset, emptyAsset, 1000, 0, 1, address(0));

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

    function testValidDepositETH(uint96 _amount) public {
        vm.assume(_amount > 10);
        uint256 amount = uint256(_amount);
        vm.deal(address(bridge), amount);

        vm.prank(address(ROLLUP_PROCESSOR));
        (uint256 outputValueA, , ) = bridge.convert(
            ethAsset,
            emptyAsset,
            sanWethAsset,
            emptyAsset,
            amount,
            0,
            0,
            address(0)
        );

        assertEq(IERC20(wethAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(IERC20(sanWethAsset.erc20Address).balanceOf(address(bridge)), outputValueA + DUST);
        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(bridge.POOLMANAGER_WETH());
        assertEq(outputValueA, (amount * 1e18) / sanRate);
    }

    function testFuzzDeposit(uint96 _amount) public {
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
    }

    function testValidWithdraw(uint96 _amount) public {
        // the protocol might not have so many sanDAI available, so we limit what can be withdrawn
        uint256 currentBalance = IERC20(daiAsset.erc20Address).balanceOf(bridge.POOLMANAGER_DAI());
        uint256 amount = uint256(bound(_amount, 10, currentBalance + 5000 ether));

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
        assertApproxEqAbs(outputValueA, (amount * sanRate) / 1e18, 2); // due to the harvest there might be a really small difference
    }

    function testFailWithdrawNoLiquidityAvailable() public {
        uint256 amount = 5000000 ether;

        uint256 balance = IERC20(sanDaiAsset.erc20Address).balanceOf(address(bridge));
        deal(sanDaiAsset.erc20Address, address(bridge), amount + balance);

        vm.prank(address(ROLLUP_PROCESSOR));
        bridge.convert(sanDaiAsset, emptyAsset, daiAsset, emptyAsset, amount, 0, 1, address(0));
    }

    function testWithdrawWithHarvest() public {
        uint256 currentBalance = IERC20(daiAsset.erc20Address).balanceOf(bridge.POOLMANAGER_DAI());
        uint256 amount = currentBalance + 10000 ether;

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
        assertApproxEqAbs(outputValueA, (amount * sanRate) / 1e18, 2);
    }

    function testValidWithdrawETH() public {
        uint96 amount = 1000;

        uint256 balance = IERC20(sanWethAsset.erc20Address).balanceOf(address(bridge));
        deal(sanWethAsset.erc20Address, address(bridge), amount + balance);

        vm.prank(address(ROLLUP_PROCESSOR));
        (uint256 outputValueA, , ) = bridge.convert(
            sanWethAsset,
            emptyAsset,
            ethAsset,
            emptyAsset,
            amount,
            0,
            1,
            address(0)
        );
        assertEq(IERC20(sanWethAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(IERC20(wethAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(address(bridge).balance, 0);
        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(bridge.POOLMANAGER_WETH());
        assertEq(outputValueA, (amount * sanRate) / 1e18);
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
        assertApproxEqAbs(outputValueA, (amount * sanRate) / 1e18, 2);
    }

    function testGetPoolManagerAndSanToken() public {
        (address poolManager, address sanToken) = bridge.getPoolManagerAndSanToken(bridge.DAI());
        assertEq(poolManager, bridge.POOLMANAGER_DAI());
        assertEq(sanToken, bridge.SANDAI());

        (poolManager, sanToken) = bridge.getPoolManagerAndSanToken(bridge.USDC());
        assertEq(poolManager, bridge.POOLMANAGER_USDC());
        assertEq(sanToken, bridge.SANUSDC());

        (poolManager, sanToken) = bridge.getPoolManagerAndSanToken(address(bridge.WETH()));
        assertEq(poolManager, bridge.POOLMANAGER_WETH());
        assertEq(sanToken, bridge.SANWETH());

        (poolManager, sanToken) = bridge.getPoolManagerAndSanToken(bridge.FRAX());
        assertEq(poolManager, bridge.POOLMANAGER_FRAX());
        assertEq(sanToken, bridge.SANFRAX());
    }
}
