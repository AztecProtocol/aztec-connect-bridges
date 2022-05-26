// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../../lib/ds-test/src/test.sol";

import {Vm} from "../../../lib/forge-std/src/Vm.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";

import {LidoBridge} from "./../../bridges/lido/LidoBridge.sol";
import {AztecTypes} from "./../../aztec/AztecTypes.sol";

contract LidoTest is DSTest {
    Vm private vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    IERC20 private wstETH = IERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

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
        uint256 wstETHBalance = wstETH.balanceOf(address(rollupProcessor));

        emit log_named_uint("After Exit ETH Balance ", afterETHBalance);
        emit log_named_uint("After Exit WstETH Balance", wstETHBalance);

        assertTrue(isAsync == false);
        assertTrue(outputValueB == 0);

        assertTrue(outputValueA != 0);
        assertTrue(wstETHBalance == 0);
        assertTrue(afterETHBalance > beforeETHBalance);
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

        assertTrue(isAsync == false);
        assertTrue(outputValueB == 0);
        assertTrue(afterETHBalance == beforeETHBalance - depositAmount);
        assertTrue(outputValueA > 0 && outputValueA <= depositAmount);
    }

}