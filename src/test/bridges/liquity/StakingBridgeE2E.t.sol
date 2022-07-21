// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {StakingBridge} from "../../../bridges/liquity/StakingBridge.sol";

contract StakingBridgeE2ETest is BridgeTestBase {
    IERC20 public constant LQTY = IERC20(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D);
    bytes32 public constant BRIDGE_PROCESSED_EVENT_SIG =
        keccak256("DefiBridgeProcessed(uint256,uint256,uint256,uint256,uint256,bool,bytes)");

    // The reference to the staking bridge
    StakingBridge private bridge;
    address private stakingContract;

    // To store the id of the staking bridge after being added
    uint256 private id;

    function setUp() public {
        // Deploy a new staking bridge and set approvals
        bridge = new StakingBridge(address(ROLLUP_PROCESSOR));
        bridge.setApprovals();

        stakingContract = address(bridge.STAKING_CONTRACT());

        // Use the label cheatcode to mark the address with "Staking Bridge" in the traces
        vm.label(address(bridge), "StakingBridge");
        vm.label(stakingContract, "LQTYStakingContract");

        // Impersonate the multi-sig to add a new bridge
        vm.startPrank(MULTI_SIG);

        // List the staking-bridge with a gasLimit of 350k
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 350000);

        // List the assets with a gasLimit of 100k
        ROLLUP_PROCESSOR.setSupportedAsset(address(LQTY), 100000);
        ROLLUP_PROCESSOR.setSupportedAsset(address(bridge), 100000);

        vm.stopPrank();

        // Fetch the id of the staking bridge
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();
    }

    // @dev In order to avoid overflows we set _depositAmount to be uint96 instead of uint256.
    function testFullDepositWithdrawalE2E(uint96 _depositAmount) public {
        vm.assume(_depositAmount > 1);

        // Use the helper function to fetch Aztec assets
        AztecTypes.AztecAsset memory lqtyAsset = getRealAztecAsset(address(LQTY));
        AztecTypes.AztecAsset memory sbAsset = getRealAztecAsset(address(bridge));

        // 1st DEPOSIT
        // Mint the depositAmount of LQTY to rollupProcessor
        deal(address(LQTY), address(ROLLUP_PROCESSOR), _depositAmount);

        // Compute deposit calldata
        uint256 bridgeCallData = encodeBridgeCallData(id, lqtyAsset, emptyAsset, sbAsset, emptyAsset, 0);

        uint256 stakingBalanceBefore = LQTY.balanceOf(stakingContract);

        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(bridgeCallData, getNextNonce(), _depositAmount, _depositAmount, 0, true, "");

        sendDefiRollup(bridgeCallData, _depositAmount);

        assertGe(
            LQTY.balanceOf(stakingContract) - stakingBalanceBefore,
            _depositAmount,
            "Staking contract balance didn't rise enough"
        );

        // 2nd WITHDRAWAL
        // Compute withdrawal calldata
        bridgeCallData = encodeBridgeCallData(id, sbAsset, emptyAsset, lqtyAsset, emptyAsset, 0);

        uint256 processorBalanceBefore = LQTY.balanceOf(address(ROLLUP_PROCESSOR));

        vm.recordLogs();
        sendDefiRollup(bridgeCallData, _depositAmount);
        Vm.Log[] memory logs = vm.getRecordedLogs();

        uint256 numEventsFound = 0;
        Vm.Log memory defiBridgeProcessedEvent;

        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == BRIDGE_PROCESSED_EVENT_SIG) {
                ++numEventsFound;
                defiBridgeProcessedEvent = logs[i];
            }
        }

        assertEq(numEventsFound, 1, "Incorrect number of events found");

        (uint256 totalInputValue, uint256 totalOutputValueA, uint256 totalOutputValueB) = abi.decode(
            defiBridgeProcessedEvent.data,
            (uint256, uint256, uint256)
        );

        assertEq(totalInputValue, _depositAmount, "Incorrect input value decoded");
        assertGe(totalOutputValueA, _depositAmount, "Output value not bigger than deposit");
        assertEq(totalOutputValueB, 0, "Output value B is not 0");

        assertGe(
            LQTY.balanceOf(address(ROLLUP_PROCESSOR)) - processorBalanceBefore,
            _depositAmount,
            "Rollup processor balance didn't rise enough"
        );
    }
}
