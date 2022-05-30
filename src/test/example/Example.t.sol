// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";
import {AztecTypes} from "./../../aztec/AztecTypes.sol";
import {Test} from "forge-std/Test.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ExampleBridgeContract} from "./../../bridges/example/ExampleBridge.sol";

contract ExampleTest is Test {
    DefiBridgeProxy internal defiBridgeProxy;
    RollupProcessor internal rollupProcessor;

    ExampleBridgeContract internal exampleBridge;

    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    function setUp() public {
        _aztecPreSetup();

        exampleBridge = new ExampleBridgeContract(address(rollupProcessor));

        rollupProcessor.setBridgeGasLimit(address(exampleBridge), 100000);
    }

    function testErrorCodes() public {
        AztecTypes.AztecAsset memory empty;

        address callerAddress = address(bytes20(uint160(uint256(keccak256("non-rollup-processor-address")))));

        vm.startPrank(callerAddress);
        vm.expectRevert(ExampleBridgeContract.InvalidCaller.selector);
        exampleBridge.convert(empty, empty, empty, empty, 0, 0, 0, address(0));
        vm.stopPrank();
    }

    function testExampleBridge() public {
        uint256 depositAmount = 15000;
        // Mint the depositAmount of Dai to rollupProcessor
        deal(address(DAI), address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(DAI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(DAI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = rollupProcessor.convert(
            address(exampleBridge),
            inputAsset,
            empty,
            outputAsset,
            empty,
            depositAmount,
            1,
            0
        );

        uint256 rollupDai = DAI.balanceOf(address(rollupProcessor));

        assertEq(depositAmount, rollupDai, "Balances must match");
    }
}
