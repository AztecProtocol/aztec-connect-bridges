// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {ISubsidy, Subsidy} from "../../../aztec/Subsidy.sol";

contract SubsidyTest is Test {
    address private constant BRIDGE = address(10);
    address private constant BENEFICIARY = address(11);

    ISubsidy private subsidy;

    event Subsidized(address indexed bridge, uint256 indexed criteria, uint128 available, uint32 gasPerMinute);
    event BeneficiaryRegistered(address indexed beneficiary);

    function setUp() public {
        subsidy = new Subsidy();

        vm.label(BRIDGE, "BRIDGE");
        vm.label(BENEFICIARY, "TEST_EOA");

        // Make sure test addresses don't hold any ETH
        vm.deal(BRIDGE, 0);
        vm.deal(BENEFICIARY, 0);
    }

    function testSettingGasUsageAndMinGasPerMinuteDoesntOverwriteAvailable() public {
        uint256 criteria = 1;
        uint32 gasUsage = 5e4;
        uint32 minGasPerMinute = 100;
        vm.prank(BRIDGE);
        subsidy.setGasUsageAndMinGasPerMinute(criteria, gasUsage, minGasPerMinute);

        subsidy.subsidize{value: 1 ether}(BRIDGE, criteria, minGasPerMinute);

        Subsidy.Subsidy memory sub = subsidy.getSubsidy(BRIDGE, 1);
        assertEq(sub.available, 1 ether, "available incorrectly set");

        vm.prank(BRIDGE);
        subsidy.setGasUsageAndMinGasPerMinute(criteria, gasUsage, minGasPerMinute);

        sub = subsidy.getSubsidy(BRIDGE, 1);
        assertEq(sub.available, 1 ether, "available got reset to 0");
    }

    function testArrayLengthsDontMatchError() public {
        // First set min gas per second values for different criteria
        uint256[] memory criteria = new uint256[](1);
        uint32[] memory gasUsage = new uint32[](2);
        uint32[] memory minGasPerMinute = new uint32[](2);

        vm.expectRevert(Subsidy.ArrayLengthsDoNotMatch.selector);
        subsidy.setGasUsageAndMinGasPerMinute(criteria, gasUsage, minGasPerMinute);
    }

    function testGasPerMinuteTooLowError() public {
        // 1st set min gas per second values for different criteria
        _setGasUsageAndMinGasPerMinute();

        vm.expectRevert(Subsidy.GasPerMinuteTooLow.selector);
        subsidy.subsidize{value: 1 ether}(BRIDGE, 1, 40);
    }

    function testAlreadySubsidizedError() public {
        // 1st set min gas per second values for different criteria
        _setGasUsageAndMinGasPerMinute();

        // 2nd subsidize criteria 3
        subsidy.subsidize{value: 1 ether}(BRIDGE, 3, 450);

        // 3rd try to set subsidy again
        vm.expectRevert(Subsidy.AlreadySubsidized.selector);
        subsidy.subsidize{value: 2 ether}(BRIDGE, 3, 500);
    }

    function testGasUsageNotSetError() public {
        vm.expectRevert(Subsidy.GasUsageNotSet.selector);
        subsidy.subsidize{value: 1 ether}(BRIDGE, 3, 550);
    }

    function testSubsidyTooLowError() public {
        // 1st set min gas per second values for different criteria
        _setGasUsageAndMinGasPerMinute();

        // 2nd check the call reverts with SubsidyTooLow error
        vm.expectRevert(Subsidy.SubsidyTooLow.selector);
        subsidy.subsidize{value: 1e17 - 1}(BRIDGE, 3, 550);
    }

    function testNotSubsidizedError() public {
        // 3rd try to set subsidy again
        vm.expectRevert(Subsidy.NotSubsidised.selector);
        subsidy.topUp{value: 2 ether}(BRIDGE, 1);
    }

    function testSubsidyGetsCorrectlySet() public {
        _setGasUsageAndMinGasPerMinute();

        subsidy.subsidize{value: 1 ether}(BRIDGE, 1, 100);

        Subsidy.Subsidy memory sub = subsidy.getSubsidy(BRIDGE, 1);

        assertEq(sub.available, 1 ether, "available incorrectly set");
        assertEq(sub.gasUsage, 5e4, "gasUsage incorrectly set");
        assertEq(sub.minGasPerMinute, 50, "minGasPerMinute incorrectly set");
        assertEq(sub.gasPerMinute, 100, "gasPerMinute incorrectly set");
        assertEq(sub.lastUpdated, block.timestamp, "lastUpdated incorrectly set");
    }

    function testEventsGetCorrectlyEmitted() public {
        _setGasUsageAndMinGasPerMinute();

        uint256 criteria = 1;
        uint32 gasPerMinute = 100;
        uint128 subsidyAmount = 1 ether;

        vm.expectEmit(true, true, false, true);
        emit Subsidized(BRIDGE, criteria, subsidyAmount, gasPerMinute);
        subsidy.subsidize{value: subsidyAmount}(BRIDGE, criteria, gasPerMinute);

        vm.expectEmit(true, true, false, true);
        emit BeneficiaryRegistered(BENEFICIARY);
        subsidy.registerBeneficiary(BENEFICIARY);
    }

    function testAllSubsidyGetsClaimedAndSubsidyCanBeRefilledAfterThat() public {
        // Set huge gasUsage and gasPerMinute so that everything can be claimed in 1 call
        uint32 gasUsage = type(uint32).max;
        vm.prank(BRIDGE);
        subsidy.setGasUsageAndMinGasPerMinute(1, gasUsage, 100);

        subsidy.subsidize{value: 1 ether}(BRIDGE, 1, 100000);
        Subsidy.Subsidy memory sub = subsidy.getSubsidy(BRIDGE, 1);
        assertEq(sub.available, 1 ether, "available incorrectly set");
        assertEq(sub.lastUpdated, block.timestamp, "lastUpdated incorrectly set");

        vm.warp(block.timestamp + 7 days);

        subsidy.registerBeneficiary(BENEFICIARY);

        vm.prank(BRIDGE);
        subsidy.claimSubsidy(1, BENEFICIARY);

        sub = subsidy.getSubsidy(BRIDGE, 1);

        assertEq(sub.available, 0, "not all subsidy was claimed");
        assertEq(sub.lastUpdated, block.timestamp, "lastUpdated incorrectly updated");

        subsidy.withdraw(BENEFICIARY);
        assertEq(BENEFICIARY.balance, 1 ether, "beneficiary didn't receive full subsidy");

        subsidy.subsidize{value: 1 ether}(BRIDGE, 1, 10000);
        sub = subsidy.getSubsidy(BRIDGE, 1);

        assertEq(sub.available, 1 ether, "available incorrectly set in refill");
    }

    function testGetAccumulatedSubsidyAmount() public {
        // Set huge gasUsage and gasPerMinute so that everything can be claimed in 1 call
        uint256 criteria = 1;
        uint32 gasUsage = type(uint32).max;
        vm.prank(BRIDGE);
        subsidy.setGasUsageAndMinGasPerMinute(criteria, gasUsage, 100);

        subsidy.subsidize{value: 1 ether}(BRIDGE, criteria, 100000);

        vm.warp(block.timestamp + 7 days);

        subsidy.registerBeneficiary(BENEFICIARY);

        uint256 accumulatedSubsidyAmount = subsidy.getAccumulatedSubsidyAmount(BRIDGE, criteria);

        vm.prank(BRIDGE);
        uint256 referenceAccumulatedSubsidyAmount = subsidy.claimSubsidy(criteria, BENEFICIARY);
        assertEq(
            accumulatedSubsidyAmount,
            referenceAccumulatedSubsidyAmount,
            "getAccumulatedSubsidyAmount(...) and claimSubsidy(...) returned different amounts"
        );
    }

    function testTopUpWorks(uint96 _value1, uint96 _value2) public {
        // Set huge gasUsage and gasPerMinute so that everything can be claimed in 1 call
        uint32 gasUsage = type(uint32).max;
        vm.prank(BRIDGE);
        subsidy.setGasUsageAndMinGasPerMinute(1, gasUsage, 100);

        uint256 value1 = bound(_value1, subsidy.MIN_SUBSIDY_VALUE(), 1000 ether);
        uint256 value2 = bound(_value2, subsidy.MIN_SUBSIDY_VALUE(), 1000 ether);
        subsidy.subsidize{value: value1}(BRIDGE, 1, 100000);
        subsidy.topUp{value: value2}(BRIDGE, 1);

        Subsidy.Subsidy memory sub = subsidy.getSubsidy(BRIDGE, 1);
        assertEq(sub.available, value1 + value2, "available incorrectly set");
    }

    function testAvailableDropsByExpectedAmountAndGetsCorrectlyWithdrawn() public {
        _setGasUsageAndMinGasPerMinute();

        uint256 dt = 3600;
        uint32 gasPerMinute = 100;

        subsidy.subsidize{value: 1 ether}(BRIDGE, 1, gasPerMinute);
        Subsidy.Subsidy memory sub = subsidy.getSubsidy(BRIDGE, 1);
        assertEq(sub.available, 1 ether, "available incorrectly set");

        uint256 expectedSubsidyAmount = ((dt * gasPerMinute) / 60) * block.basefee;

        vm.warp(block.timestamp + dt);

        subsidy.registerBeneficiary(BENEFICIARY);

        vm.prank(BRIDGE);
        uint256 subsidyAmount = subsidy.claimSubsidy(1, BENEFICIARY);

        assertEq(subsidyAmount, expectedSubsidyAmount);
        assertEq(
            subsidyAmount,
            subsidy.claimableAmount(BENEFICIARY),
            "subsidyAmount differs from beneficiary's withdrawable balance"
        );

        sub = subsidy.getSubsidy(BRIDGE, 1);

        assertEq(sub.available, 1 ether - subsidyAmount, "unexpected value of available");

        subsidy.withdraw(BENEFICIARY);
        assertEq(subsidyAmount, BENEFICIARY.balance, "withdrawable balance was not withdrawn");
    }

    function testZeroClaims() public {
        _setGasUsageAndMinGasPerMinute();

        uint256 dt = 3600;
        uint32 gasPerMinute = 100;

        subsidy.subsidize{value: 1 ether}(BRIDGE, 1, gasPerMinute);
        Subsidy.Subsidy memory sub = subsidy.getSubsidy(BRIDGE, 1);
        assertEq(sub.available, 1 ether, "available incorrectly set");

        vm.warp(block.timestamp + dt);
        vm.startPrank(BRIDGE);
        assertEq(subsidy.claimSubsidy(1, address(0)), 0);
        assertEq(subsidy.claimSubsidy(1, BENEFICIARY), 0);
    }

    function testEthTransferFailed() public {
        _setGasUsageAndMinGasPerMinute();

        uint256 dt = 3600;
        uint32 gasPerMinute = 100;

        subsidy.subsidize{value: 1 ether}(BRIDGE, 1, gasPerMinute);
        Subsidy.Subsidy memory sub = subsidy.getSubsidy(BRIDGE, 1);
        assertEq(sub.available, 1 ether, "available incorrectly set");

        vm.warp(block.timestamp + dt);

        subsidy.registerBeneficiary(address(this));

        vm.startPrank(BRIDGE);
        subsidy.claimSubsidy(1, address(this));

        vm.expectRevert(Subsidy.EthTransferFailed.selector);
        subsidy.withdraw(address(this));
    }

    function testClaimSameBlock() public {
        _setGasUsageAndMinGasPerMinute();

        uint256 dt = 3600;
        uint32 gasPerMinute = 100;

        subsidy.subsidize{value: 1 ether}(BRIDGE, 1, gasPerMinute);
        Subsidy.Subsidy memory sub = subsidy.getSubsidy(BRIDGE, 1);
        assertEq(sub.available, 1 ether, "available incorrectly set");

        uint256 expectedSubsidyAmount = ((dt * gasPerMinute) / 60) * block.basefee;

        vm.warp(block.timestamp + dt);

        subsidy.registerBeneficiary(BENEFICIARY);
        assertTrue(subsidy.isRegistered(BENEFICIARY));

        vm.prank(BRIDGE);
        uint256 subsidyAmount = subsidy.claimSubsidy(1, BENEFICIARY);
        uint256 subsidyAmount2 = subsidy.claimSubsidy(1, BENEFICIARY);
        assertEq(subsidyAmount2, 0, "Second claim in same block not 0");

        assertEq(subsidyAmount, expectedSubsidyAmount);
        assertEq(
            subsidyAmount,
            subsidy.claimableAmount(BENEFICIARY),
            "subsidyAmount differs from beneficiary's withdrawable balance"
        );

        sub = subsidy.getSubsidy(BRIDGE, 1);

        assertEq(sub.available, 1 ether - subsidyAmount, "unexpected value of available");

        subsidy.withdraw(BENEFICIARY);
        assertEq(subsidyAmount, BENEFICIARY.balance, "withdrawable balance was not withdrawn");
    }

    function _setGasUsageAndMinGasPerMinute() private {
        uint256[] memory criteria = new uint256[](4);
        uint32[] memory gasUsage = new uint32[](4);
        uint32[] memory minGasPerMinute = new uint32[](4);

        criteria[0] = 1;
        criteria[1] = 2;
        criteria[2] = 3;
        criteria[3] = 4;

        gasUsage[0] = 5e4;
        gasUsage[1] = 10e4;
        gasUsage[2] = 15e4;
        gasUsage[3] = 20e4;

        minGasPerMinute[0] = 50;
        minGasPerMinute[1] = 100;
        minGasPerMinute[2] = 150;
        minGasPerMinute[3] = 200;

        vm.prank(BRIDGE);
        subsidy.setGasUsageAndMinGasPerMinute(criteria, gasUsage, minGasPerMinute);
    }
}
