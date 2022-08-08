// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

// Example-specific imports
import {IERC4626} from "../../../interfaces/erc4626/IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC4626Bridge} from "../../../bridges/erc4626/ERC4626Bridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

contract ERC4626E2ETest is BridgeTestBase {
    IERC20 public constant MAPLE = IERC20(0x33349B282065b0284d756F0577FB39c158F935e6);
    IERC4626 public constant VAULT = IERC4626(0x4937A209D4cDbD3ecD48857277cfd4dA4D82914c);
    ERC4626Bridge internal bridge;

    uint256 private id;

    AztecTypes.AztecAsset mapleAsset;
    AztecTypes.AztecAsset vaultAsset;

    function setUp() public {
        bridge = new ERC4626Bridge(address(ROLLUP_PROCESSOR));

        vm.label(address(bridge), "ERC4626 Bridge");
        vm.label(address(MAPLE), "MAPLE");
        vm.label(address(VAULT), "VAULT");

        vm.startPrank(MULTI_SIG);

        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 1000000);

        ROLLUP_PROCESSOR.setSupportedAsset(address(MAPLE), 100000);
        ROLLUP_PROCESSOR.setSupportedAsset(address(VAULT), 100000);
        vm.stopPrank();

        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        mapleAsset = getRealAztecAsset(address(MAPLE));
        vaultAsset = getRealAztecAsset(address(VAULT));
    }

    function test4626E2ETest(uint96 _depositAmount) public {
        vm.assume(_depositAmount > 1);

        deal(address(MAPLE), address(ROLLUP_PROCESSOR), _depositAmount);
        bridge.listVault(address(VAULT));
        uint256 bridgeCallData = encodeBridgeCallData(id, mapleAsset, emptyAsset, vaultAsset, emptyAsset, 0);

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = sendDefiRollup(bridgeCallData, _depositAmount);

        assertGt(outputValueA, 0, "zero outputValueA");
        assertEq(outputValueB, 0, "Non-zero outputValueB");
        assertFalse(isAsync, "Bridge is not synchronous");
    }
}
