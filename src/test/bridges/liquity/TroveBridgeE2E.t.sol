// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {TroveBridge} from "../../../bridges/liquity/TroveBridge.sol";
import {TroveBridgeTestBase} from "./TroveBridgeTestBase.sol";

contract TroveBridgeE2ETest is BridgeTestBase, TroveBridgeTestBase {
    // To store the id of the trove bridge after being added
    uint256 private id;

    AztecTypes.AztecAsset private ethAsset;
    AztecTypes.AztecAsset private tbAsset;
    AztecTypes.AztecAsset private lusdAsset;

    function setUp() public {
        // Deploy a new trove bridge
        vm.prank(OWNER);
        bridge = new TroveBridge(address(ROLLUP_PROCESSOR), 160);

        // Use the label cheat-code to mark the address with "Trove Bridge" in the traces
        vm.label(address(bridge), "TroveBridge");

        _baseSetUp();

        // Impersonate the multi-sig to add a new bridge
        vm.startPrank(MULTI_SIG);

        // List trove bridge with a gasLimit of 500k
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 10000000);

        // List the assets with a gasLimit of 100k
        ROLLUP_PROCESSOR.setSupportedAsset(tokens["LUSD"].addr, 100000);
        ROLLUP_PROCESSOR.setSupportedAsset(address(bridge), 100000);

        vm.stopPrank();

        // Setup assets
        ethAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        tbAsset = ROLLUP_ENCODER.getRealAztecAsset(address(bridge));
        lusdAsset = ROLLUP_ENCODER.getRealAztecAsset(tokens["LUSD"].addr);

        // Fetch the id of the trove bridge
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        _openTrove();
    }

    function testFullFlow(uint96 _collateral) public {
        uint256 collateral = bound(_collateral, 1e17, 1e21);

        _borrow(collateral);
        _repay(collateral);
    }

    function testFullFlowRepayingWithColl(uint96 _collateral) public {
        // Setting maximum only to 100 ETH because liquidity in the UNI pools is not sufficient for higher amounts
        uint256 collateral = bound(_collateral, 1e17, 1e20);

        _borrow(collateral);
        _repayWithCollateral(collateral);
    }

    function _borrow(uint256 _collateral) private {
        // Mint the collateral amount of ETH to rollupProcessor
        vm.deal(address(ROLLUP_PROCESSOR), _collateral);

        // Compute borrow calldata
        ROLLUP_ENCODER.defiInteractionL2(id, ethAsset, emptyAsset, tbAsset, lusdAsset, MAX_FEE, _collateral);

        (uint256 debtBeforeBorrowing, uint256 collBeforeBorrowing, , ) = TROVE_MANAGER.getEntireDebtAndColl(
            address(bridge)
        );

        (uint256 outputValueA, uint256 outputValueB, ) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        (uint256 debtAfterBorrowing, uint256 collAfterBorrowing, , ) = TROVE_MANAGER.getEntireDebtAndColl(
            address(bridge)
        );
        assertEq(
            collAfterBorrowing - collBeforeBorrowing,
            _collateral,
            "Collateral increase differs from deposited collateral"
        );
        uint256 tbBalanceAfterBorrowing = bridge.balanceOf(address(ROLLUP_PROCESSOR));
        assertEq(
            debtAfterBorrowing - debtBeforeBorrowing,
            tbBalanceAfterBorrowing,
            "Debt increase differs from processor's TB balance"
        );
        assertEq(outputValueA, tbBalanceAfterBorrowing, "Debt amount doesn't equal outputValueA");
        assertEq(
            outputValueB,
            bridge.computeAmtToBorrow(_collateral),
            "Borrowed amount doesn't equal expected borrow amount"
        );
    }

    function _repay(uint256 _collateral) private {
        uint256 tbBalance = bridge.balanceOf(address(ROLLUP_PROCESSOR));

        // Mint the amount to repay to rollup processor - sufficient amount is not there since borrowing because we
        // need to pay for the borrowing fee
        deal(lusdAsset.erc20Address, address(ROLLUP_PROCESSOR), tbBalance + bridge.DUST());

        // Compute repay calldata
        ROLLUP_ENCODER.defiInteractionL2(id, tbAsset, lusdAsset, ethAsset, lusdAsset, 0, tbBalance);

        (uint256 outputValueA, uint256 outputValueB, ) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        assertApproxEqAbs(outputValueA, _collateral, 1, "output value differs from collateral by more than 1 wei");
        assertEq(outputValueB, 0, "Non-zero LUSD amount returned");
    }

    function _repayWithCollateral(uint256 _collateral) private {
        uint256 tbBalance = bridge.balanceOf(address(ROLLUP_PROCESSOR));

        // Mint the amount to repay to rollup processor - sufficient amount is not there since borrowing because we
        // need to pay for the borrowing fee
        deal(lusdAsset.erc20Address, address(ROLLUP_PROCESSOR), tbBalance + bridge.DUST());

        // Compute repay calldata
        ROLLUP_ENCODER.defiInteractionL2(id, tbAsset, emptyAsset, ethAsset, emptyAsset, _getPrice(-1e20), tbBalance);

        (uint256 outputValueA, , ) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        // Given that ICR was set to 160% and the debt has been repaid with collateral, received collateral should be
        // approx. equal to (deposit collateral amount) * (100/160). Given that borrowing fee and fee for the flash
        // swap was paid the actual collateral received will be slightly less.
        uint256 expectedEthReceived = _collateral - (_collateral * 100) / 160;
        uint256 expectedEthReceivedWithTolerance = (expectedEthReceived * 90) / 100;

        assertGt(outputValueA, expectedEthReceivedWithTolerance, "Not enough collateral received");
    }
}
