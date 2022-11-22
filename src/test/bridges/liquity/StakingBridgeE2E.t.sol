// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {StakingBridge} from "../../../bridges/liquity/StakingBridge.sol";

contract StakingBridgeE2ETest is BridgeTestBase {
    IERC20 public constant LQTY = IERC20(0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D);

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

        // List the staking-bridge with a gasLimit of 500k
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 500000);

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
        AztecTypes.AztecAsset memory lqtyAsset = ROLLUP_ENCODER.getRealAztecAsset(address(LQTY));
        AztecTypes.AztecAsset memory sbAsset = ROLLUP_ENCODER.getRealAztecAsset(address(bridge));

        // DEPOSIT
        // Mint the depositAmount of LQTY to rollupProcessor
        deal(address(LQTY), address(ROLLUP_PROCESSOR), _depositAmount);

        // Compute deposit calldata
        uint256 bridgeCallData =
            ROLLUP_ENCODER.defiInteractionL2(id, lqtyAsset, emptyAsset, sbAsset, emptyAsset, 0, _depositAmount);

        uint256 stakingBalanceBefore = LQTY.balanceOf(stakingContract);

        ROLLUP_ENCODER.registerEventToBeChecked(
            bridgeCallData, ROLLUP_ENCODER.getNextNonce(), _depositAmount, _depositAmount, 0, true, ""
        );
        ROLLUP_ENCODER.processRollup();

        assertGe(
            LQTY.balanceOf(stakingContract) - stakingBalanceBefore,
            _depositAmount,
            "Staking contract balance didn't rise enough"
        );
        assertEq(
            bridge.balanceOf(address(ROLLUP_PROCESSOR)), _depositAmount, "Incorrect SB balance of rollup processor"
        );

        // WITHDRAWAL
        // Compute withdrawal calldata
        ROLLUP_ENCODER.defiInteractionL2(id, sbAsset, emptyAsset, lqtyAsset, emptyAsset, 0, _depositAmount);

        uint256 processorBalanceBefore = LQTY.balanceOf(address(ROLLUP_PROCESSOR));

        (uint256 outputValueA, uint256 outputValueB,) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        assertGe(outputValueA, _depositAmount, "Output value not bigger than deposit");
        assertEq(outputValueB, 0, "Output value B is not 0");

        assertGe(
            LQTY.balanceOf(address(ROLLUP_PROCESSOR)) - processorBalanceBefore,
            _depositAmount,
            "Rollup processor balance didn't rise enough"
        );
    }
}
