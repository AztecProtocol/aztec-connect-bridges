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
    bytes32 public constant BRIDGE_PROCESSED_EVENT_SIG =
        keccak256("DefiBridgeProcessed(uint256,uint256,uint256,uint256,uint256,bool,bytes)");

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
        uint256 collateral = bound(0, 1e18, 1e20);

        // Use the helper function to fetch Aztec assets
        AztecTypes.AztecAsset memory ethAsset = getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory tbAsset = getRealAztecAsset(address(bridge));
        AztecTypes.AztecAsset memory lusdAsset = getRealAztecAsset(tokens["LUSD"].addr);

        // 1st BORROW
        // Mint the collateral amount of ETH to rollupProcessor
        deal(tokens["LUSD"].addr, address(ROLLUP_PROCESSOR), collateral);

        // Compute borrow calldata
        uint256 bridgeCallData = encodeBridgeCallData(id, ethAsset, emptyAsset, tbAsset, lusdAsset, MAX_FEE);

        uint256 amtToBorrow = bridge.computeAmtToBorrow(collateral);

        uint256 price = TROVE_MANAGER.priceFeed().fetchPrice();
        uint256 icr = 1600000000000000000;
        uint256 roundingError = 1;
        // Note: if rounding starts causing issues simply fetch the event as a whole, decode and check diff is small
        // enough
        uint256 tbBalanceAfterBorrowing = (collateral * price) / icr - roundingError;

        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(
            bridgeCallData,
            getNextNonce(),
            collateral,
            tbBalanceAfterBorrowing,
            amtToBorrow,
            true,
            ""
        );

        sendDefiRollup(bridgeCallData, collateral);

        assertEq(
            bridge.balanceOf(address(ROLLUP_PROCESSOR)),
            tbBalanceAfterBorrowing,
            "Incorrect TB balance of rollup processor"
        );

        // 2nd REPAY
        // Mint the amount to repay to rollup processor
        deal(lusdAsset.erc20Address, address(ROLLUP_PROCESSOR), tbBalanceAfterBorrowing + bridge.DUST());

        // Compute repay calldata
        bridgeCallData = encodeBridgeCallData(id, tbAsset, lusdAsset, ethAsset, lusdAsset, MAX_FEE);

        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(bridgeCallData, getNextNonce(), tbBalanceAfterBorrowing, collateral, 0, true, "");

        sendDefiRollup(bridgeCallData, tbBalanceAfterBorrowing);
    }
}
