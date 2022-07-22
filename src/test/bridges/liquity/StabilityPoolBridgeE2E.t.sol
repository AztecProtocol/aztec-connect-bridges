// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {StabilityPoolBridge} from "../../../bridges/liquity/StabilityPoolBridge.sol";

contract StabilityPoolBridgeE2ETest is BridgeTestBase {
    IERC20 public constant LUSD = IERC20(0x5f98805A4E8be255a32880FDeC7F6728C6568bA0);

    // The reference to the stability pool bridge
    StabilityPoolBridge private bridge;
    address private stabilityPool;

    // To store the id of the stability pool bridge after being added
    uint256 private id;

    function setUp() public {
        // Deploy a new stability pool bridge and set approvals
        bridge = new StabilityPoolBridge(address(ROLLUP_PROCESSOR), address(0));
        bridge.setApprovals();

        stabilityPool = address(bridge.STABILITY_POOL());

        // Use the label cheat-code to mark the address with stability pool bridge in the traces
        vm.label(address(bridge), "StabilityPoolBridge");
        vm.label(stabilityPool, "StabilityPool");

        // Impersonate the multi-sig to add a new bridge
        vm.startPrank(MULTI_SIG);

        // List the staking-bridge with a gasLimit of 350k
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 1000000);

        // List the assets with a gasLimit of 100k
        ROLLUP_PROCESSOR.setSupportedAsset(address(LUSD), 100000);
        ROLLUP_PROCESSOR.setSupportedAsset(address(bridge), 100000);

        vm.stopPrank();

        // Fetch the id of the stability pool bridge
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();
    }

    // @dev In order to avoid overflows we set _depositAmount to be uint96 instead of uint256.
    function testFullDepositWithdrawalE2E(uint96 _depositAmount) public {
        vm.assume(_depositAmount > 1);

        // Use the helper function to fetch Aztec assets
        AztecTypes.AztecAsset memory lusdAsset = getRealAztecAsset(address(LUSD));
        AztecTypes.AztecAsset memory spbAsset = getRealAztecAsset(address(bridge));

        // 1st DEPOSIT
        // Mint the depositAmount of LUSD to rollupProcessor
        deal(address(LUSD), address(ROLLUP_PROCESSOR), _depositAmount);

        // Compute deposit calldata
        uint256 bridgeCallData = encodeBridgeCallData(id, lusdAsset, emptyAsset, spbAsset, emptyAsset, 0);

        uint256 stabilityPoolBalanceBefore = LUSD.balanceOf(stabilityPool);

        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(bridgeCallData, getNextNonce(), _depositAmount, _depositAmount, 0, true, "");

        sendDefiRollup(bridgeCallData, _depositAmount);

        assertGe(
            LUSD.balanceOf(stabilityPool) - stabilityPoolBalanceBefore,
            _depositAmount,
            "Stability pool balance didn't rise enough"
        );
        assertEq(
            bridge.balanceOf(address(ROLLUP_PROCESSOR)),
            _depositAmount,
            "Incorrect SPB balance of rollup processor"
        );

        // 2nd WITHDRAWAL
        // Compute withdrawal calldata
        bridgeCallData = encodeBridgeCallData(id, spbAsset, emptyAsset, lusdAsset, emptyAsset, 0);

        uint256 processorBalanceBefore = LUSD.balanceOf(address(ROLLUP_PROCESSOR));

        vm.recordLogs();
        sendDefiRollup(bridgeCallData, _depositAmount);
        (uint256 totalInputValue, uint256 totalOutputValueA, uint256 totalOutputValueB) = getDefiBridgeProcessedEvent();

        assertEq(totalInputValue, _depositAmount, "Incorrect input value decoded");
        assertGe(totalOutputValueA, _depositAmount, "Output value not bigger than deposit");
        assertEq(totalOutputValueB, 0, "Output value B is not 0");

        assertGe(
            LUSD.balanceOf(address(ROLLUP_PROCESSOR)) - processorBalanceBefore,
            _depositAmount,
            "Rollup processor balance didn't rise enough"
        );
    }
}
