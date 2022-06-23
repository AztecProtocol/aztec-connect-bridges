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
    ExampleBridgeContract internal bridge;

    // To store the id of the example bridge after being added
    uint256 private id;

    function setUp() public {
        // Deploy a new example bridge
        bridge = new ExampleBridgeContract(address(ROLLUP_PROCESSOR));

        // use the label cheatcode to mark the address with "Example Bridge" in the traces
        vm.label(address(bridge), "Example Bridge");

        // Impersonate the multi-sig to add a new bridge
        vm.prank(MULTI_SIG);

        // List the example-bridge with a gasLimit of 100K
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 100000);

        // Fetch the id of the example bridge
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();
    }

    function testInvalidCaller(address _callerAddress) public {
        vm.assume(_callerAddress != address(ROLLUP_PROCESSOR));
        vm.prank(_callerAddress);
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function testInvalidInputAssetType() public {
        vm.prank(address(ROLLUP_PROCESSOR));
        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    // @notice The purpose of this test is to directly test convert functionality of the bridge.
    // @dev In order to avoid overflows we set _depositAmount to be uint96 instead of uint256.
    function testExampleBridgeUnitTest(uint96 _depositAmount) public {
        // Define input and output assets
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(DAI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetA = inputAssetA;

        // Rollup processor transfers ERC20 tokens to the bridge before calling convert. Since we are calling
        // bridge.convert(...) function directly we have to transfer the funds in the test on our own. In this case
        // we'll solve it by directly minting the _depositAmount of Dai to the bridge.
        deal(address(DAI), address(bridge), _depositAmount);

        // Store dai balance before interaction to be able to verify the balance after interaction is correct
        uint256 daiBalanceBefore = DAI.balanceOf(address(ROLLUP_PROCESSOR));

        // Impersonate rollup processor
        vm.startPrank(address(ROLLUP_PROCESSOR));

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
            inputAssetA, // _inputAssetA - definition of an input asset
            emptyAsset, // _inputAssetB - not used so can be left empty
            outputAssetA, // _outputAssetA - in this example equal to input asset
            emptyAsset, // _outputAssetB - not used so can be left empty
            _depositAmount, // _inputValue - an amount of input asset A sent to the bridge
            0, // _interactionNonce
            0, // _auxData - not used in the example bridge
            address(0) // _rollupBeneficiary - not relevant in this context
        );

        // Now we transfer the funds back from the bridge to the rollup processor
        // In this case input asset equals output asset so I only work with the input asset definition
        // Basically in all the real world use-cases output assets would differ from input assets
        IERC20(inputAssetA.erc20Address).transferFrom(address(bridge), address(ROLLUP_PROCESSOR), outputValueA);

        vm.stopPrank();

        assertEq(outputValueA, _depositAmount, "Output value A doesn't equal deposit amount");
        assertEq(outputValueB, 0, "Output value B is not 0");
        assertTrue(!isAsync, "Bridge is incorrectly in an async mode");

        uint256 daiBalanceAfter = DAI.balanceOf(address(ROLLUP_PROCESSOR));

        assertEq(daiBalanceAfter - daiBalanceBefore, _depositAmount, "Balances must match");
    }

    /**
     * @notice The purpose of this test is to test the bridge in an environment that is as close to the final
     *         deployment as possible without spinning up all the rollup infrastructure (sequencer, proof generator
     *         etc.).
     * @dev In order to avoid overflows we set _depositAmount to be uint96 instead of uint256.
     */
    function testExampleBridgeE2ETest(uint96 _depositAmount) public {
        vm.assume(_depositAmount > 1);

        // Use the helper function to fetch the support AztecAsset for DAI
        AztecTypes.AztecAsset memory daiAsset = getRealAztecAsset(address(DAI));

        // Mint the depositAmount of Dai to rollupProcessor
        deal(address(DAI), address(ROLLUP_PROCESSOR), _depositAmount);

        // Computes the encoded data for the specific bridge interaction
        uint256 bridgeId = encodeBridgeId(id, daiAsset, emptyAsset, daiAsset, emptyAsset, 0);

        // Use cheatcodes to look for event matching 2 first indexed values and data
        vm.expectEmit(true, true, false, true);
        // Second part of cheatcode, emit the event that we are to match against.
        emit DefiBridgeProcessed(bridgeId, getNextNonce(), _depositAmount, _depositAmount, 0, true, "");

        // Execute the rollup with the bridge interaction. Ensure that event as seen above is emitted.
        sendDefiRollup(bridgeId, _depositAmount);

        // Check that the balance of the rollup is same as before interaction (bridge just sends funds back)
        assertEq(_depositAmount, DAI.balanceOf(address(ROLLUP_PROCESSOR)), "Balances must match");

        // Perform a second rollup with half the deposit, perform similar checks.
        uint256 secondDeposit = _depositAmount / 2;
        // Use cheatcodes to look for event matching 2 first indexed values and data
        vm.expectEmit(true, true, false, true);
        // Second part of cheatcode, emit the event that we are to match against.
        emit DefiBridgeProcessed(bridgeId, getNextNonce(), secondDeposit, secondDeposit, 0, true, "");

        // Execute the rollup with the bridge interaction. Ensure that event as seen above is emitted.
        sendDefiRollup(bridgeId, secondDeposit);

        // Check that the balance of the rollup is same as before interaction (bridge just sends funds back)
        assertEq(_depositAmount, DAI.balanceOf(address(ROLLUP_PROCESSOR)), "Balances must match");
    }
}
