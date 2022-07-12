// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IssuanceBridge} from "../../../bridges/set/IssuanceBridge.sol";
import {IController} from "../../../interfaces/set/IController.sol";
import {ISetToken} from "../../../interfaces/set/ISetToken.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {Test} from "forge-std/Test.sol";

contract SetUnitTest is Test {
    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 public constant DPI = IERC20(0x1494CA1F11D487c2bBe4543E90080AeBa4BA3C2b);

    AztecTypes.AztecAsset internal emptyAsset;

    address private rollupProcessor;

    IssuanceBridge internal bridge;

    // @dev This method exists on RollupProcessor.sol. It's defined here in order to be able to receive ETH like a real
    //      rollup processor would.
    function receiveEthFromBridge(uint256 _interactionNonce) external payable {}

    function setUp() public {
        // In unit tests we set address of rollupProcessor to the address of this test contract
        rollupProcessor = address(this);

        bridge = new IssuanceBridge(rollupProcessor);

        address[] memory tokens = new address[](2);
        tokens[0] = address(DAI);
        tokens[1] = address(DPI);
        bridge.approveTokens(tokens);

        vm.label(tokens[0], "DAI");
        vm.label(tokens[1], "DPI");
    }

    function testInvalidCaller() public {
        vm.prank(address(124));
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function test0InputValue() public {
        vm.expectRevert(ErrorLib.InvalidInput.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function testSetBridge() public {
        // test if we can prefund rollup with tokens and ETH
        uint256 depositAmountDai = 1e9;
        uint256 depositAmountDpi = 2e9;
        uint256 depositAmountEth = 1 ether;

        deal(address(DAI), rollupProcessor, depositAmountDai);
        deal(address(DPI), rollupProcessor, depositAmountDpi);
        deal(rollupProcessor, depositAmountEth);

        uint256 rollupBalanceDai = DAI.balanceOf(rollupProcessor);
        uint256 rollupBalanceDpi = DPI.balanceOf(rollupProcessor);
        uint256 rollupBalanceEth = rollupProcessor.balance;

        assertEq(depositAmountDai, rollupBalanceDai, "DAI balance must match");

        assertEq(depositAmountDpi, rollupBalanceDpi, "DPI balance must match");

        assertEq(depositAmountEth, rollupBalanceEth, "ETH balance must match");
    }

    function testIssueSetForExactToken() public {
        // Pre-fund contract with DAI
        uint256 depositAmountDai = 1e21; // 1000 DAI
        deal(address(DAI), address(bridge), depositAmountDai);

        // DAI is input
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(DAI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        // DPI is output
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(DPI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        // Call bridge's convert function
        (uint256 outputValueA, , ) = bridge.convert(
            inputAsset,
            emptyAsset,
            outputAsset,
            emptyAsset,
            depositAmountDai,
            0,
            0,
            address(0)
        );

        IERC20(outputAsset.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueA);

        uint256 rollupBalanceAfterDai = DAI.balanceOf(rollupProcessor);
        uint256 rollupBalanceAfterDpi = DPI.balanceOf(rollupProcessor);

        assertEq(0, rollupBalanceAfterDai, "DAI balance after convert must match");

        assertEq(outputValueA, rollupBalanceAfterDpi, "DPI balance after convert must match");

        assertGt(rollupBalanceAfterDpi, 0, "DPI balance after must be > 0");
    }

    function testIssueSetForExactEth() public {
        // Pre-fund contract with ETH
        uint256 depositAmountEth = 1e17; // 0.1 ETH
        deal(address(bridge), depositAmountEth);

        // DAI is input
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            assetType: AztecTypes.AztecAssetType.ETH
        });

        // DAI is output
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(DPI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (uint256 outputValueA, , ) = bridge.convert(
            inputAsset,
            emptyAsset,
            outputAsset,
            emptyAsset,
            depositAmountEth,
            0,
            0,
            address(0)
        );

        IERC20(outputAsset.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueA);

        uint256 rollupBalanceAfterDpi = DPI.balanceOf(rollupProcessor);

        assertEq(outputValueA, rollupBalanceAfterDpi, "DPI balance after convert must match");

        assertGt(rollupBalanceAfterDpi, 0, "DPI balance after must be > 0");
    }

    function testRedeemExactSetForToken() public {
        // Pre-fund bridge contract DPI
        uint256 depositAmountDpi = 1e20; // 100 DPI
        deal(address(DPI), address(bridge), depositAmountDpi);

        // DPI is input
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(DPI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        // DAI is output
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(DAI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        // Call bridge's convert function
        (uint256 outputValueA, , ) = bridge.convert(
            inputAsset,
            emptyAsset,
            outputAsset,
            emptyAsset,
            depositAmountDpi,
            0,
            0,
            address(0)
        );

        IERC20(outputAsset.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueA);

        uint256 rollupBalanceAfterDai = DAI.balanceOf(rollupProcessor);
        uint256 rollupBalanceAfterDpi = DPI.balanceOf(rollupProcessor);

        // Checks after
        assertEq(outputValueA, rollupBalanceAfterDai, "DAI balance after convert must match");

        assertEq(rollupBalanceAfterDpi, 0, "DPI balance after convert must match");

        assertGt(rollupBalanceAfterDai, 0, "DAI balance after must be > 0");
    }

    function testRedeemExactSetForEth() public {
        // prefund bridge with tokens
        uint256 depositAmountDpi = 1e20; // 100 DPI
        deal(address(DPI), address(bridge), depositAmountDpi);

        // Maker sure rollupProcessor's ETH balance is 0
        deal(rollupProcessor, 0);

        // DPI is input
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(DPI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        // ETH is output
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            assetType: AztecTypes.AztecAssetType.ETH
        });

        (uint256 outputValueA, , ) = bridge.convert(
            inputAsset,
            emptyAsset,
            outputAsset,
            emptyAsset,
            depositAmountDpi,
            0,
            0,
            address(0)
        );

        // Checks after
        assertEq(DPI.balanceOf(rollupProcessor), 0, "DPI balance after convert must be 0");
        assertEq(outputValueA, rollupProcessor.balance, "ETH balance after convert must match");
    }
}
