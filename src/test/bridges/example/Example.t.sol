// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ExampleBridgeContract} from "../../../bridges/example/ExampleBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

contract ExampleTest is BridgeTestBase {
    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    // The reference to the example bridge
    ExampleBridgeContract internal exampleBridge;

    // To store the id of the example bridge after being added
    uint256 private id;

    function setUp() public {
        // Deploy a new example bridge
        exampleBridge = new ExampleBridgeContract(address(ROLLUP_PROCESSOR));

        // use the label cheatcode to mark the address with "Example Bridge" in the traces
        vm.label(address(exampleBridge), "Example Bridge");

        // Impersonate the multi-sig to add a new bridge
        vm.prank(MULTI_SIG);

        // List the example-bridge with a gasLimit of 100K
        ROLLUP_PROCESSOR.setSupportedBridge(address(exampleBridge), 100000);

        // Fetch the id of the example bridge
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();
    }

    function testErrorCodes(address _callerAddress) public {
        vm.assume(_callerAddress != address(ROLLUP_PROCESSOR));
        vm.prank(_callerAddress);
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        exampleBridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function testExampleBridge(uint256 _depositAmount) public {
        uint256 depositAmount = bound(_depositAmount, 2, type(uint96).max);

        // Use the helper function to fetch the support AztecAsset for DAI
        AztecTypes.AztecAsset memory daiAsset = getRealAztecAsset(address(DAI));

        // Mint the depositAmount of Dai to rollupProcessor
        deal(address(DAI), address(ROLLUP_PROCESSOR), depositAmount);

        // Computes the encoded data for the specific bridge interaction
        uint256 bridgeId = encodeBridgeId(id, daiAsset, emptyAsset, daiAsset, emptyAsset, 0);

        // Use cheatcodes to look for event matching 2 first events and data
        vm.expectEmit(true, true, false, true);
        // Second part of cheatcode, emit the event that we are to match against.
        emit DefiBridgeProcessed(bridgeId, getNextNonce(), depositAmount, depositAmount, 0, true, "");

        // Execute the rollup with the bridge interaction. Ensure that event as seen above is emitted.
        sendDefiRollup(bridgeId, depositAmount);

        // Check that the balance of the rollup is same as before interaction (bridge just sends funds back)
        assertEq(depositAmount, DAI.balanceOf(address(ROLLUP_PROCESSOR)), "Balances must match");

        // Perform a second rollup with half the deposit, perform similar checks.
        uint256 secondDeposit = depositAmount / 2;
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(bridgeId, getNextNonce(), secondDeposit, secondDeposit, 0, true, "");
        sendDefiRollup(bridgeId, secondDeposit);

        assertEq(depositAmount, DAI.balanceOf(address(ROLLUP_PROCESSOR)), "Balances must match");
    }
}
