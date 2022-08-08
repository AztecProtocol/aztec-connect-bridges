// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

// Example-specific imports
import {IERC4626} from "../../../interfaces/erc4626/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {VaultBridge} from "../../../bridges/erc4626/VaultBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

/**
 * @notice The purpose of this test is to test the bridge in an environment that is as close to the final deployment
 *         as possible without spinning up all the rollup infrastructure (sequencer, proof generator etc.).
 */
contract ERC4626E2ETest is BridgeTestBase {
    IERC20 public constant MAPLE = IERC20(0x33349B282065b0284d756F0577FB39c158F935e6);
    IERC4626 public constant VAULT = IERC4626(0x4937A209D4cDbD3ecD48857277cfd4dA4D82914c);
    // The reference to the example bridge
    VaultBridge internal bridge;

    // To store the id of the example bridge after being added
    uint256 private id;

    // @dev In order to avoid overflows we set _depositAmount to be uint96 instead of uint256.
    function test4626E2ETest(uint96 _depositAmount) public {
        bridge = new VaultBridge(address(ROLLUP_PROCESSOR));

        // Use the label cheatcode to mark the address with "Example Bridge" in the traces
        vm.label(address(bridge), "ERC4626 Bridge");

        // Impersonate the multi-sig to add a new bridge
        vm.startPrank(MULTI_SIG);

        // List the example-bridge with a gasLimit of 100K
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 1000000);

        ROLLUP_PROCESSOR.setSupportedAsset(address(MAPLE), 100000);
        ROLLUP_PROCESSOR.setSupportedAsset(address(VAULT), 100000);
        vm.stopPrank();

        // Fetch the id of the example bridge
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();
        vm.assume(_depositAmount > 1);

        AztecTypes.AztecAsset memory mapleAsset = getRealAztecAsset(address(MAPLE));
        AztecTypes.AztecAsset memory vaultAsset = getRealAztecAsset(address(VAULT));
        // Mint the depositAmount of Dai to rollupProcessor
        deal(address(MAPLE), address(ROLLUP_PROCESSOR), _depositAmount);
        bridge.approvePair(address(VAULT), address(MAPLE));
        // Computes the encoded data for the specific bridge interaction
        // encodeBridgeCallData(id, daiAsset, emptyAsset, daiAsset, emptyAsset, 0);
        uint256 bridgeCallData = encodeBridgeCallData(id, mapleAsset, emptyAsset, vaultAsset, emptyAsset, 0);

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = sendDefiRollup(bridgeCallData, _depositAmount);
        uint256 rollupMAPLEToken = MAPLE.balanceOf(address(bridge));
        // Note: Unlike in unit tests there is no need to manually transfer the tokens - RollupProcessor does this

        // Check the output values are as expected
        assertEq(outputValueA, _depositAmount - 1, "outputValueA doesn't equal deposit");
        assertEq(outputValueB, 0, "Non-zero outputValueB");
        assertFalse(isAsync, "Bridge is not synchronous");
    }
}
