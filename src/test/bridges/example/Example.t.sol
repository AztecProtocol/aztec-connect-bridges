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
    ExampleBridgeContract internal exampleBridge;

    uint256 private id;

    function setUp() public {
        exampleBridge = new ExampleBridgeContract(address(ROLLUP_PROCESSOR));
        vm.label(address(exampleBridge), "Example Bridge");
        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(exampleBridge), 100000);
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
        AztecTypes.AztecAsset memory daiAsset = getRealAztecAsset(address(DAI));

        // Mint the depositAmount of Dai to rollupProcessor
        deal(address(DAI), address(ROLLUP_PROCESSOR), depositAmount);

        uint256 bridgeId = encodeBridgeId(id, daiAsset, emptyAsset, daiAsset, emptyAsset, 0);
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(bridgeId, getNextNonce(), depositAmount, depositAmount, 0, true, "");
        sendDefiRollup(bridgeId, depositAmount);

        assertEq(depositAmount, DAI.balanceOf(address(ROLLUP_PROCESSOR)), "Balances must match");

        uint256 secondDeposit = depositAmount / 2;
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(bridgeId, getNextNonce(), secondDeposit, secondDeposit, 0, true, "");
        sendDefiRollup(bridgeId, secondDeposit);

        assertEq(depositAmount, DAI.balanceOf(address(ROLLUP_PROCESSOR)), "Balances must match");
    }
}
