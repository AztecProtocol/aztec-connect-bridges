// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {NotionalBridgeContract} from "../../../bridges/notional/NotionalBridge.sol";
import {IWrappedfCashFactory} from "../../../interfaces/notional/IWrappedfCashFactory.sol";
import {NotionalViews} from "../../../interfaces/notional/INotionalViews.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

contract NotionalE2ETest is BridgeTestBase {
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    NotionalBridgeContract private bridge;
    IWrappedfCashFactory public constant FCASH_FACTORY =
        IWrappedfCashFactory(0x5D051DeB5db151C2172dCdCCD42e6A2953E27261);
    NotionalViews public constant NOTIONAL_VIEW = NotionalViews(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    // To store the id of the notional bridge after being added
    uint256 private id;

    function setUp() public {
        // Deploy a new notional bridge and set approvals
        bridge = new NotionalBridgeContract(address(ROLLUP_PROCESSOR));
        bridge.preApproveForAll();
        // Use the label cheat-code to mark the address in the traces
        vm.label(address(bridge), "NotionalBridge");

        // Impersonate the multi-sig to add a new bridge
        vm.startPrank(MULTI_SIG);

        // List the staking-bridge with a gasLimit of 350k
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 1000000);

        vm.stopPrank();

        // Fetch the id of the notional bridge
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();
    }

    function testFullDepositWithdrawalE2E(uint256 _depositAmount) public {
        _depositAmount = bound(_depositAmount, 1e16, 1e22);
        address fcash = 0xfcB060E09e452EEFf142949Bec214c187CDF25fA;

        // Use the helper function to fetch Aztec assets
        // Add support for our fcash token
        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedAsset(fcash, 200000);
        AztecTypes.AztecAsset memory daiAsset = getRealAztecAsset(DAI);
        AztecTypes.AztecAsset memory fcashAsset = getRealAztecAsset(fcash);
        // DEPOSIT
        vm.deal(address(ROLLUP_PROCESSOR), _depositAmount);
        // Compute deposit calldata
        uint256 bridgeCallData = encodeBridgeCallData(id, daiAsset, emptyAsset, fcashAsset, emptyAsset, 1);

        (uint256 outputValueA, , ) = sendDefiRollup(bridgeCallData, _depositAmount);
        assertEq(
            ERC20(fcash).balanceOf(address(ROLLUP_PROCESSOR)),
            outputValueA,
            "Incorrect fcash balance of rollup processor"
        );
        // WITHDRAWAL
        // Compute withdrawal calldata
        bridgeCallData = encodeBridgeCallData(id, fcashAsset, emptyAsset, daiAsset, emptyAsset, 0);

        uint256 daiBalanceBefore = ERC20(DAI).balanceOf(address(ROLLUP_PROCESSOR));

        (outputValueA, , ) = sendDefiRollup(bridgeCallData, ERC20(fcash).balanceOf(address(ROLLUP_PROCESSOR)));
        uint256 daiBalanceAfter = ERC20(DAI).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 daiWithdrew = daiBalanceAfter - daiBalanceBefore;
        assertGt(daiWithdrew, 0, "Zero withdraw amount");
        assertGt(daiWithdrew * 10000, _depositAmount * 9900, "Should take most of money back");
    }
}
