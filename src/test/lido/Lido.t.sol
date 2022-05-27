// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import 'forge-std/Test.sol';

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";

import {LidoBridge} from "./../../bridges/lido/LidoBridge.sol";
import {AztecTypes} from "./../../aztec/AztecTypes.sol";

contract LidoTest is Test {
    IERC20 private wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    error INVALID_CONFIGURATION();
    error INVALID_CALLER();
    error INVALID_INPUT();
    error INVALID_OUTPUT();
    error INVALID_WRAP_RETURN_VALUE();
    error INVALID_UNWRAP_RETURN_VALUE();
    error ASYNC_DISABLED();

    event DefiBridgeProcessed(
        uint256 indexed bridgeId,
        uint256 indexed nonce,
        uint256 totalInputValue,
        uint256 totalOutputValueA,
        uint256 totalOutputValueB,
        bool result,
        bytes errorReason
    );

    DefiBridgeProxy private defiBridgeProxy;
    RollupProcessor private rollupProcessor;

    LidoBridge private bridge;

    AztecTypes.AztecAsset private empty;
    AztecTypes.AztecAsset private ethAsset = AztecTypes.AztecAsset({
        id: 1,
        erc20Address: address(0),
        assetType: AztecTypes.AztecAssetType.ETH
    });
    AztecTypes.AztecAsset private wstETHAsset = AztecTypes.AztecAsset({
        id: 2,
        erc20Address: address(wstETH),
        assetType: AztecTypes.AztecAssetType.ERC20
    });

    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    function setUp() public {
        _aztecPreSetup();
        bridge = new LidoBridge(address(rollupProcessor), address(rollupProcessor));
    }

    function testErrorCodes() public {
        // TODO: INVALID_CONFIGURATION test
        // vm.expectRevert(INVALID_CONFIGURATION());

        vm.expectRevert(INVALID_CALLER.selector);
        bridge.convert(
            empty,
            empty,
            empty,
            empty,
            0,
            0,
            0,
            address(0)
        );

        vm.startPrank(address(rollupProcessor));
        
        vm.expectRevert(INVALID_INPUT.selector);
        bridge.convert(
            empty,
            empty,
            empty,
            empty,
            0,
            0,
            0,
            address(0)
        );

        vm.expectRevert(INVALID_OUTPUT.selector);
        bridge.convert(
            ethAsset,
            empty,
            empty,
            empty,
            0,
            0,
            0,
            address(0)
        );

        vm.expectRevert(INVALID_OUTPUT.selector);
        bridge.convert(
            wstETHAsset,
            empty,
            empty,
            empty,
            0,
            0,
            0,
            address(0)
        );
        
        vm.expectRevert(ASYNC_DISABLED.selector);
        bridge.finalise(
            wstETHAsset,
            empty,
            empty,
            empty,
            0,
            0
        );

        vm.stopPrank();
    }

    function testLidoBridge() public {
        validateLidoBridge(100e18, 50e18);
        validateLidoBridge(500000e18, 400000e18);
    }

    function testLidoDepositAll(uint128 depositAmount) public {
        vm.assume(depositAmount > 1000);
        validateLidoBridge(depositAmount, depositAmount);
    }

    function testLidoDepositPartial(uint128 balance) public {
        vm.assume(balance > 1000);
        validateLidoBridge(balance, balance / 2);
    }

    function testMultipleDeposits(uint80 a, uint80 b) public {
        vm.assume(a > 1000 && b > 1000);
        vm.deal(address(rollupProcessor), uint256(a) + b);

        // Convert ETH to wstETH
        validateETHToWstETH(a);
        validateETHToWstETH(b);
    }

    function testDepositThenPartialWithdraw(uint80 a) public {
        vm.assume(a > 1000);
        vm.deal(address(rollupProcessor), a);

        validateETHToWstETH(a);

        validateWstETHToETH(wstETH.balanceOf(address(rollupProcessor)) / 2);
    }

    /**
        Testing flow:
        1. Send ETH to bridge
        2. Get back wstETH
        3. Send wstETH to bridge
        4. Get back ETH
     */
    function validateLidoBridge(uint256 balance, uint256 depositAmount) public {
        // Send ETH to bridge

        vm.deal(address(rollupProcessor), balance);

        // Convert ETH to wstETH
        validateETHToWstETH(depositAmount);
        
        // convert wstETH back to ETH using the same bridge
        validateWstETHToETH(wstETH.balanceOf(address(rollupProcessor)));

    }

    function validateWstETHToETH(uint256 depositAmount) public {
        uint256 beforeETHBalance = address(rollupProcessor).balance;
        uint256 beforeWstEthBalance = wstETH.balanceOf(address(rollupProcessor));

        (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        ) = rollupProcessor.convert(
            address(bridge),
            wstETHAsset,
            empty,
            ethAsset,
            empty,
            depositAmount,
            2,
            0
        );

        uint256 afterETHBalance = address(rollupProcessor).balance;
        uint256 afterWstETHBalance = wstETH.balanceOf(address(rollupProcessor));

        emit log_named_uint("After Exit ETH Balance ", afterETHBalance);
        emit log_named_uint("After Exit WstETH Balance", afterWstETHBalance);

        assertFalse(isAsync, 'Async interaction');
        assertEq(outputValueB, 0, 'OutputValueB not 0');
        assertGt(outputValueA, 0, 'No Eth received');
        assertEq(afterETHBalance, beforeETHBalance + outputValueA, 'ETH balance not maching');
        assertEq(afterWstETHBalance, beforeWstEthBalance - depositAmount, 'WST ETH balance not matching');
    }

    function validateETHToWstETH(uint256 depositAmount) public {
        uint256 beforeETHBalance = address(rollupProcessor).balance;
        uint256 beforeWstETHBalance = wstETH.balanceOf(address(rollupProcessor));

        emit log_named_uint("Before ETH Balance", beforeETHBalance);
        emit log_named_uint("Before WstETHBalance", beforeWstETHBalance);

        (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        ) = rollupProcessor.convert(
                address(bridge),
                ethAsset,
                empty,
                wstETHAsset,
                empty,
                depositAmount,
                1,
                0
        );

        uint256 afterETHBalance = address(rollupProcessor).balance;
        uint256 afterWstETHBalance = wstETH.balanceOf(address(rollupProcessor));

        emit log_named_uint("After ETH Balance", afterETHBalance);
        emit log_named_uint("After WstETHBalance", afterWstETHBalance);

        assertFalse(isAsync, 'Async interaction');
        assertEq(outputValueB, 0, 'OutputValueB not 0');
        assertEq(afterETHBalance, beforeETHBalance - depositAmount, 'ETH balance not matching');
        assertGt(outputValueA, 0, 'No WST ETH received');
        assertEq(afterWstETHBalance, beforeWstETHBalance + outputValueA, 'WST ETH balance not matching');
    }

}