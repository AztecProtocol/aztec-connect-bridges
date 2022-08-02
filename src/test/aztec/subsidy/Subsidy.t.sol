// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {ISubsidy, Subsidy} from "../../../aztec/Subsidy.sol";

contract SubsidyTest is Test {
    address private constant BRIDGE = address(10);

    ISubsidy private subsidy;

    function setUp() public {
        subsidy = new Subsidy();
    }

    function testArrayLengthsDontMatchError() public {
        // First set min gas per second values for different criterias
        uint256[] memory criterias = new uint256[](1);
        uint64[] memory gasUsages = new uint64[](2);

        vm.expectRevert(Subsidy.ArrayLengthsDoNotMatch.selector);
        subsidy.setGasUsage(criterias, gasUsages);
    }

    function testGasPerSecondTooLowError() public {
        // 1st set min gas per second values for different criterias
        _setGasUsage();

        vm.expectRevert(Subsidy.GasPerSecondTooLow.selector);
        subsidy.subsidize{value: 1 ether}(BRIDGE, 1, 9);
    }

    function testAlreadySubsidizedError() public {
        // 1st set min gas per second values for different criterias
        _setGasUsage();

        // 2nd subsidize criteria 3
        subsidy.subsidize{value: 1 ether}(BRIDGE, 3, 45);

        // 3rd try to set subsidy again
        vm.expectRevert(Subsidy.AlreadySubsidized.selector);
        subsidy.subsidize{value: 2 ether}(BRIDGE, 3, 50);
    }

    function testGasUsageNotSetError() public {
        vm.expectRevert(Subsidy.GasUsageNotSet.selector);
        subsidy.subsidize{value: 1 ether}(BRIDGE, 3, 55);
    }

    function testSubsidyTooLowError() public {
        // 1st set min gas per second values for different criterias
        _setGasUsage();

        // 2nd check the call reverts with SubsidyTooLow error
        vm.expectRevert(Subsidy.SubsidyTooLow.selector);
        subsidy.subsidize{value: 1e17 - 1}(BRIDGE, 3, 55);
    }

    function testBridgeRevertsIfBeneficiaryDoesntImplementReceive() public {
        // 1st set min gas per second values for different criterias
        _setGasUsage();

        subsidy.subsidize{value: 1 ether}(BRIDGE, 1, 10);
    }

    function _setGasUsage() private {
        uint256[] memory criterias = new uint256[](4);
        uint64[] memory gasUsage = new uint64[](4);

        criterias[0] = 1;
        criterias[1] = 2;
        criterias[2] = 3;
        criterias[3] = 4;

        gasUsage[0] = 10 * 7 days;
        gasUsage[1] = 20 * 7 days;
        gasUsage[2] = 30 * 7 days;
        gasUsage[3] = 40 * 7 days;

        vm.prank(BRIDGE);
        subsidy.setGasUsage(criterias, gasUsage);
    }
}
