// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {DefiBridgeProxy} from "../../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "../../../aztec/RollupProcessor.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {Test} from "forge-std/Test.sol";

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
        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(exampleBridge), 100000);
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();
    }

    function testErrorCodes() public {
        AztecTypes.AztecAsset memory empty;

        address callerAddress = address(bytes20(uint160(uint256(keccak256("non-rollup-processor-address")))));

        vm.prank(callerAddress);
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        exampleBridge.convert(empty, empty, empty, empty, 0, 0, 0, address(0));
    }

    function testExampleBridge() public {
        AztecTypes.AztecAsset memory empty;
        // This is a little annoying, because we are not really using the erc20 address here, we are using using the Id. We might want to give an error?
        AztecTypes.AztecAsset memory daiAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(DAI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        uint256 depositAmount = 15000;

        // Mint the depositAmount of Dai to rollupProcessor
        deal(address(DAI), address(ROLLUP_PROCESSOR), depositAmount);

        uint256 bridgeId = encodeBridgeId(id, daiAsset, empty, daiAsset, empty, 0);
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(bridgeId, getNextNonce(), depositAmount, depositAmount, 0, true, "");
        sendDefiRollup(bridgeId, depositAmount);

        assertEq(depositAmount, DAI.balanceOf(address(ROLLUP_PROCESSOR)), "Balances must match");

        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(bridgeId, getNextNonce(), depositAmount / 2, depositAmount / 2, 0, true, "");
        sendDefiRollup(bridgeId, depositAmount / 2);

        assertEq(depositAmount, DAI.balanceOf(address(ROLLUP_PROCESSOR)), "Balances must match");
    }
}
