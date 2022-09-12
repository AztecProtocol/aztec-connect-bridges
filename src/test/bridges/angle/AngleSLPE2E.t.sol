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

    AztecTypes.AztecAsset private ethAsset;

    AztecTypes.AztecAsset private daiAsset;
    AztecTypes.AztecAsset private usdcAsset;
    AztecTypes.AztecAsset private wethAsset;

    AztecTypes.AztecAsset private sanDaiAsset;
    AztecTypes.AztecAsset private sanUsdcAsset;
    AztecTypes.AztecAsset private sanWethAsset;

    AngleSLPBridge internal bridge;
    uint256 internal id;

    uint256 internal constant DUST = 1;

    address private constant BENEFICIARY = address(uint160(uint256(keccak256(abi.encodePacked("_BENEFICIARY")))));

    function setUp() public {
        emit log_named_uint("block number", block.number);
        bridge = new AngleSLPBridge(address(ROLLUP_PROCESSOR));
        vm.label(address(bridge), "ANGLE_BRIDGE");
        vm.deal(address(bridge), 0);

        vm.startPrank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 1500000);
        ROLLUP_PROCESSOR.setSupportedAsset(0x7B8E89b0cE7BAC2cfEC92A371Da899eA8CBdb450, 80000); // sanDAI
        ROLLUP_PROCESSOR.setSupportedAsset(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, 80000); // USDC
        ROLLUP_PROCESSOR.setSupportedAsset(0x9C215206Da4bf108aE5aEEf9dA7caD3352A36Dad, 80000); // sanUSDC
        ROLLUP_PROCESSOR.setSupportedAsset(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2, 80000); // weth
        ROLLUP_PROCESSOR.setSupportedAsset(0x30c955906735e48D73080fD20CB488518A6333C8, 80000); // sanWETH
        vm.stopPrank();

        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        ethAsset = getRealAztecAsset(address(0));

        daiAsset = getRealAztecAsset(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        sanDaiAsset = getRealAztecAsset(0x7B8E89b0cE7BAC2cfEC92A371Da899eA8CBdb450);

        usdcAsset = getRealAztecAsset(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
        sanUsdcAsset = getRealAztecAsset(0x9C215206Da4bf108aE5aEEf9dA7caD3352A36Dad);

        wethAsset = getRealAztecAsset(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
        sanWethAsset = getRealAztecAsset(0x30c955906735e48D73080fD20CB488518A6333C8);

        deal(daiAsset.erc20Address, address(bridge), DUST);
        deal(sanDaiAsset.erc20Address, address(bridge), DUST);
        deal(usdcAsset.erc20Address, address(bridge), DUST);
        deal(sanUsdcAsset.erc20Address, address(bridge), DUST);
        deal(wethAsset.erc20Address, address(bridge), DUST);
        deal(sanWethAsset.erc20Address, address(bridge), DUST);

        // since the rollup doesn't have USDC, we deal some to it
        deal(usdcAsset.erc20Address, address(ROLLUP_PROCESSOR), 100000e6);

        // Subsidize
        SUBSIDY.subsidize{value: 10 ether}(address(bridge), 0, 500);
        SUBSIDY.subsidize{value: 10 ether}(address(bridge), 1, 500);
        SUBSIDY.registerBeneficiary(BENEFICIARY);

        setRollupBeneficiary(BENEFICIARY);
    }

    function testValidDeposit(uint96 _amount) public {
        _testValidDeposit(daiAsset, sanDaiAsset, _amount, bridge.POOLMANAGER_DAI());
        assertGt(SUBSIDY.claimableAmount(BENEFICIARY), 0, "Claimable was not updated");
    }

    function testValidDepositETH(uint96 _amount) public {
        uint256 balanceRollupBeforeETH = address(ROLLUP_PROCESSOR).balance;
        uint256 amount = uint256(_amount);
        amount = bound(amount, 10, balanceRollupBeforeETH - 1);

        vm.warp(block.timestamp + 1 days); // warp to increase subsidy

        uint256 balanceRollupBeforeSanWETH = IERC20(sanWethAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));

        uint256 bridgeCallData = encodeBridgeCallData(id, ethAsset, emptyAsset, sanWethAsset, emptyAsset, 0);
        (uint256 outputValueA, , ) = sendDefiRollup(bridgeCallData, amount);

        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(bridge.POOLMANAGER_WETH());

        assertEq(outputValueA, (amount * 1e18) / sanRate);
        assertEq(address(bridge).balance, 0);
        assertEq(IERC20(sanWethAsset.erc20Address).balanceOf(address(bridge)), DUST);

        uint256 balanceRollupAfterETH = address(ROLLUP_PROCESSOR).balance;
        uint256 balanceRollupAfterSanWETH = IERC20(sanWethAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));

        assertEq(balanceRollupAfterETH, balanceRollupBeforeETH - amount);
        assertEq(balanceRollupAfterSanWETH, balanceRollupBeforeSanWETH + outputValueA);

        assertGt(SUBSIDY.claimableAmount(BENEFICIARY), 0, "Claimable was not updated");
    }

    function testValidWithdraw(uint96 _amount) public {
        // the protocol might not have so many sanDAI available, so we limit what can be withdrawn
        uint256 amount = uint256(bound(_amount, 10, 100000 ether));

        vm.warp(block.timestamp + 1 days); // warp to increase subsidy
        _testValidWithdraw(sanDaiAsset, daiAsset, amount, bridge.POOLMANAGER_DAI());
        assertGt(SUBSIDY.claimableAmount(BENEFICIARY), 0, "Claimable was not updated");
    }

    function testValidWithdrawETH() public {
        uint256 amount = 1000;

        deal(sanWethAsset.erc20Address, address(ROLLUP_PROCESSOR), amount);

        uint256 balanceRollupBeforeETH = address(ROLLUP_PROCESSOR).balance;

        uint256 bridgeCallData = encodeBridgeCallData(id, sanWethAsset, emptyAsset, ethAsset, emptyAsset, 1);
        (uint256 outputValueA, , ) = sendDefiRollup(bridgeCallData, amount);

        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(bridge.POOLMANAGER_WETH());

        assertEq(outputValueA, (amount * sanRate) / 1e18);
        assertEq(address(bridge).balance, 0);
        assertEq(IERC20(sanWethAsset.erc20Address).balanceOf(address(bridge)), DUST);

        uint256 balanceRollupAfterETH = address(ROLLUP_PROCESSOR).balance;

        assertEq(balanceRollupAfterETH, balanceRollupBeforeETH + outputValueA);
    }

    function testDepositUSDC(uint96 _amount) public {
        _testValidDeposit(usdcAsset, sanUsdcAsset, _amount, bridge.POOLMANAGER_USDC());
        assertGt(SUBSIDY.claimableAmount(BENEFICIARY), 0, "Claimable was not updated");
    }

    function testWithdrawUSDC(uint96 _amount) public {
        // the protocol might not have so many sanUSDC available, so we limit what can be withdrawn
        uint256 amount = uint256(bound(_amount, 10, 100000e6));

        vm.warp(block.timestamp + 1 days); // warp to increase subsidy
        _testValidWithdraw(sanUsdcAsset, usdcAsset, amount, bridge.POOLMANAGER_USDC());
        assertGt(SUBSIDY.claimableAmount(BENEFICIARY), 0, "Claimable was not updated");
    }

    function _testValidDeposit(
        AztecTypes.AztecAsset memory _inputAsset,
        AztecTypes.AztecAsset memory _outputAsset,
        uint96 _amount,
        address _poolManager
    ) internal {
        uint256 balanceRollupBeforeInput = IERC20(_inputAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 amount = uint256(_amount);
        amount = bound(amount, 10, balanceRollupBeforeInput - 1);

        vm.warp(block.timestamp + 1 days); // warp to increase subsidy

        uint256 balanceRollupBeforeOutput = IERC20(_outputAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));

        uint256 bridgeCallData = encodeBridgeCallData(id, _inputAsset, emptyAsset, _outputAsset, emptyAsset, 0);
        (uint256 outputValueA, , ) = sendDefiRollup(bridgeCallData, amount);

        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(_poolManager);

        assertEq(outputValueA, (amount * 1e18) / sanRate);
        assertEq(IERC20(_inputAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(IERC20(_outputAsset.erc20Address).balanceOf(address(bridge)), DUST);

        uint256 balanceRollupAfterInput = IERC20(_inputAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 balanceRollupAfterOutput = IERC20(_outputAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));

        assertEq(balanceRollupAfterInput, balanceRollupBeforeInput - amount);
        assertEq(balanceRollupAfterOutput, balanceRollupBeforeOutput + outputValueA);
    }

    function _testValidWithdraw(
        AztecTypes.AztecAsset memory _inputAsset,
        AztecTypes.AztecAsset memory _outputAsset,
        uint256 _amount,
        address _poolManager
    ) internal {
        deal(_inputAsset.erc20Address, address(ROLLUP_PROCESSOR), _amount);

        uint256 balanceRollupBeforeOutput = IERC20(_outputAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 balanceRollupBeforeInput = IERC20(_inputAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));

        uint256 bridgeCallData = encodeBridgeCallData(id, _inputAsset, emptyAsset, _outputAsset, emptyAsset, 1);
        (uint256 outputValueA, , ) = sendDefiRollup(bridgeCallData, _amount);

        (, , , , , uint256 sanRate, , , ) = bridge.STABLE_MASTER().collateralMap(_poolManager);

        assertApproxEqAbs(outputValueA, (_amount * sanRate) / 1e18, 2);
        assertEq(IERC20(_outputAsset.erc20Address).balanceOf(address(bridge)), DUST);
        assertEq(IERC20(_inputAsset.erc20Address).balanceOf(address(bridge)), DUST);

        uint256 balanceRollupAfterOutput = IERC20(_outputAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 balanceRollupAfterIntput = IERC20(_inputAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR));

        assertEq(balanceRollupAfterOutput, balanceRollupBeforeOutput + outputValueA);
        assertEq(balanceRollupAfterIntput, balanceRollupBeforeInput - _amount);
    }
}
