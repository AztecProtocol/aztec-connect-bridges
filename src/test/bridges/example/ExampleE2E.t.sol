// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ExampleBridgeContract} from "../../../bridges/example/ExampleBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

/**
 * @notice The purpose of this test is to test the bridge in an environment that is as close to the final deployment
 *         as possible without spinning up all the rollup infrastructure (sequencer, proof generator etc.).
 */
contract ExampleE2ETest is BridgeTestBase {
    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    // The reference to the example bridge
    ExampleBridgeContract internal bridge;

    // To store the id of the example bridge after being added
    uint256 private id;

    function setUp() public {
        // Deploy a new example bridge
        bridge = new ExampleBridgeContract(address(ROLLUP_PROCESSOR));

        // Use the label cheatcode to mark the address with "Example Bridge" in the traces
        vm.label(address(bridge), "Example Bridge");

        // Impersonate the multi-sig to add a new bridge
        vm.prank(MULTI_SIG);

        // List the example-bridge with a gasLimit of 100K
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 100000);

        // Fetch the id of the example bridge
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();
    }

    // @dev In order to avoid overflows we set _depositAmount to be uint96 instead of uint256.
    function testExampleBridgeE2ETest(uint96 _depositAmount) public {
        vm.assume(_depositAmount > 1);

        // Use the helper function to fetch the support AztecAsset for DAI
        AztecTypes.AztecAsset memory daiAsset = getRealAztecAsset(address(DAI));

        // Mint the depositAmount of Dai to rollupProcessor
        deal(address(DAI), address(ROLLUP_PROCESSOR), _depositAmount);

        // Computes the encoded data for the specific bridge interaction
        uint256 bridgeCallData = encodeBridgeCallData(id, daiAsset, emptyAsset, daiAsset, emptyAsset, 0);

        // Use cheatcodes to look for event matching 2 first indexed values and data
        vm.expectEmit(true, true, false, true);
        // Second part of cheatcode, emit the event that we are to match against.
        emit DefiBridgeProcessed(bridgeCallData, getNextNonce(), _depositAmount, _depositAmount, 0, true, "");

        // Execute the rollup with the bridge interaction. Ensure that event as seen above is emitted.
        sendDefiRollup(bridgeCallData, _depositAmount);

        // Check that the balance of the rollup is same as before interaction (bridge just sends funds back)
        assertEq(_depositAmount, DAI.balanceOf(address(ROLLUP_PROCESSOR)), "Balances must match");

        // Perform a second rollup with half the deposit, perform similar checks.
        uint256 secondDeposit = _depositAmount / 2;
        // Use cheatcodes to look for event matching 2 first indexed values and data
        vm.expectEmit(true, true, false, true);
        // Second part of cheatcode, emit the event that we are to match against.
        emit DefiBridgeProcessed(bridgeCallData, getNextNonce(), secondDeposit, secondDeposit, 0, true, "");

        // Execute the rollup with the bridge interaction. Ensure that event as seen above is emitted.
        sendDefiRollup(bridgeCallData, secondDeposit);

        // Check that the balance of the rollup is same as before interaction (bridge just sends funds back)
        assertEq(_depositAmount, DAI.balanceOf(address(ROLLUP_PROCESSOR)), "Balances must match");
    }
}
