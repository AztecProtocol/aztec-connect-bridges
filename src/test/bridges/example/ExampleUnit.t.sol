// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ExampleBridgeContract} from "../../../bridges/example/ExampleBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {ISubsidy, Subsidy} from "../../../aztec/Subsidy.sol";

// @notice The purpose of this test is to directly test convert functionality of the bridge.
contract ExampleUnitTest is Test {
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant BENEFICIARY = address(11);

    AztecTypes.AztecAsset private emptyAsset;
    address private rollupProcessor;
    ISubsidy private subsidy;
    // The reference to the example bridge
    ExampleBridgeContract private bridge;

    // @dev This method exists on RollupProcessor.sol. It's defined here in order to be able to receive ETH like a real
    //      rollup processor would.
    function receiveEthFromBridge(uint256 _interactionNonce) external payable {}

    function setUp() public {
        // In unit tests we set address of rollupProcessor to the address of this test contract
        rollupProcessor = address(this);

        // Deploy the Subsidy contract in order to be able to test subsidy
        subsidy = new Subsidy();

        // Deploy a new example bridge
        bridge = new ExampleBridgeContract(rollupProcessor, subsidy);

        // Set ETH balance to 0 for clarity (somebody sent ETH to that address on mainnet)
        vm.deal(address(bridge), 0);

        // Use the label cheatcode to mark the address with "Example Bridge" in the traces
        vm.label(address(bridge), "Example Bridge");

        // Subsidize the bridge when used with Dai and register a beneficiary
        uint256 criteria = bridge.computeCriteria(DAI, DAI);
        uint32 gasPerMinute = 200;
        subsidy.subsidize{value: 1 ether}(address(bridge), criteria, gasPerMinute);

        subsidy.registerBeneficiary{value: 1}(BENEFICIARY);

        // Make sure beneficiary holds only 1 wei of ETH (to make testing easy)
        vm.deal(BENEFICIARY, 1);
    }

    function testInvalidCaller(address _callerAddress) public {
        vm.assume(_callerAddress != rollupProcessor);
        // Use HEVM cheatcode to call from a different address than is address(this)
        vm.prank(_callerAddress);
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function testInvalidInputAssetType() public {
        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    // @notice The purpose of this test is to directly test convert functionality of the bridge.
    // @dev In order to avoid overflows we set _depositAmount to be uint96 instead of uint256.
    function testExampleBridgeUnitTest(uint96 _depositAmount) public {
        vm.warp(block.timestamp + 1 days);

        // Define input and output assets
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: DAI,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetA = inputAssetA;

        // Rollup processor transfers ERC20 tokens to the bridge before calling convert. Since we are calling
        // bridge.convert(...) function directly we have to transfer the funds in the test on our own. In this case
        // we'll solve it by directly minting the _depositAmount of Dai to the bridge.
        deal(DAI, address(bridge), _depositAmount);

        // Store dai balance before interaction to be able to verify the balance after interaction is correct
        uint256 daiBalanceBefore = IERC20(DAI).balanceOf(rollupProcessor);

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
            inputAssetA, // _inputAssetA - definition of an input asset
            emptyAsset, // _inputAssetB - not used so can be left empty
            outputAssetA, // _outputAssetA - in this example equal to input asset
            emptyAsset, // _outputAssetB - not used so can be left empty
            _depositAmount, // _totalInputValue - an amount of input asset A sent to the bridge
            0, // _interactionNonce
            0, // _auxData - not used in the example bridge
            BENEFICIARY // _rollupBeneficiary - address, the subsidy will be sent to
        );

        // Now we transfer the funds back from the bridge to the rollup processor
        // In this case input asset equals output asset so I only work with the input asset definition
        // Basically in all the real world use-cases output assets would differ from input assets
        IERC20(inputAssetA.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueA);

        assertEq(outputValueA, _depositAmount, "Output value A doesn't equal deposit amount");
        assertEq(outputValueB, 0, "Output value B is not 0");
        assertTrue(!isAsync, "Bridge is incorrectly in an async mode");

        uint256 daiBalanceAfter = IERC20(DAI).balanceOf(rollupProcessor);

        assertEq(daiBalanceAfter - daiBalanceBefore, _depositAmount, "Balances must match");

        assertGt(BENEFICIARY.balance, 0, "Subsidy was not claimed");
    }
}
