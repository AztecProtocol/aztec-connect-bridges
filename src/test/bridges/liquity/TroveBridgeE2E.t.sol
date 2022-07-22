// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {TroveBridge} from "../../../bridges/liquity/TroveBridge.sol";
import {TroveBridgeTestBase} from "./TroveBridgeTestBase.sol";

contract TroveBridgeE2ETest is BridgeTestBase, TroveBridgeTestBase {
    // To store the id of the trove bridge after being added
    uint256 private id;

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

        // Fetch the id of the trove bridge
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        _openTrove();
    }

    // @dev In order to avoid overflows we set _depositAmount to be uint96 instead of uint256.
    function testFullFlow(uint96 _collateral) public {
        uint256 collateral = bound(_collateral, 1e17, 1e21);

        // Use the helper function to fetch Aztec assets
        AztecTypes.AztecAsset memory ethAsset = getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory tbAsset = getRealAztecAsset(address(bridge));
        AztecTypes.AztecAsset memory lusdAsset = getRealAztecAsset(tokens["LUSD"].addr);

        // BORROW
        // Mint the collateral amount of ETH to rollupProcessor
        vm.deal(address(ROLLUP_PROCESSOR), collateral);

        // Compute borrow calldata
        uint256 bridgeCallData = encodeBridgeCallData(id, ethAsset, emptyAsset, tbAsset, lusdAsset, MAX_FEE);

        uint256 processorLusdBalanceBefore = tokens["LUSD"].erc.balanceOf(address(ROLLUP_PROCESSOR));
        (uint256 debtBeforeBorrowing, uint256 collBeforeBorrowing, , ) = TROVE_MANAGER.getEntireDebtAndColl(
            address(bridge)
        );

        sendDefiRollup(bridgeCallData, collateral);

        (uint256 debtAfterBorrowing, uint256 collAfterBorrowing, , ) = TROVE_MANAGER.getEntireDebtAndColl(
            address(bridge)
        );
        assertEq(
            collAfterBorrowing - collBeforeBorrowing,
            collateral,
            "Collateral increase differs from deposited collateral"
        );
        uint256 tbBalanceAfterBorrowing = bridge.balanceOf(address(ROLLUP_PROCESSOR));
        assertEq(
            debtAfterBorrowing - debtBeforeBorrowing,
            tbBalanceAfterBorrowing,
            "Debt increase differs from processor's TB balance"
        );
        assertEq(
            tokens["LUSD"].erc.balanceOf(address(ROLLUP_PROCESSOR)) - processorLusdBalanceBefore,
            bridge.computeAmtToBorrow(collateral),
            "Borrowed amount doesn't equal expected borrow amount"
        );

        // REPAY
        // Mint the amount to repay to rollup processor - sufficient amount is not there since borrowing because there
        // we need to pay for the borrowing fee
        deal(lusdAsset.erc20Address, address(ROLLUP_PROCESSOR), tbBalanceAfterBorrowing + bridge.DUST());

        // Compute repay calldata
        bridgeCallData = encodeBridgeCallData(id, tbAsset, lusdAsset, ethAsset, lusdAsset, MAX_FEE);

        vm.recordLogs();
        sendDefiRollup(bridgeCallData, tbBalanceAfterBorrowing);
        (, uint256 totalOutputValueA, uint256 totalOutputValueB) = getDefiBridgeProcessedData();

        assertApproxEqAbs(totalOutputValueA, collateral, 1, "output value differs from colalteral by more than 1 wei");
        assertEq(totalOutputValueB, 0, "Non-zero LUSD amount returned");
    }
}
