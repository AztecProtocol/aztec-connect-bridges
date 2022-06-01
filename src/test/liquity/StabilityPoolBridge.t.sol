// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {AztecTypes} from "../../aztec/AztecTypes.sol";

import {TestUtil} from "./utils/TestUtil.sol";
import {StabilityPoolBridge} from "../../bridges/liquity/StabilityPoolBridge.sol";

contract StabilityPoolBridgeTest is TestUtil {
    StabilityPoolBridge private bridge;

    function setUp() public {
        _aztecPreSetup();
        setUpTokens();

        bridge = new StabilityPoolBridge(address(rollupProcessor), address(0));
        bridge.setApprovals();

        // Set LUSD bridge balance to 1 WEI
        // Necessary for the optimization based on EIP-1087 to work!
        deal(tokens["LUSD"].addr, address(bridge), 1);

        // Set LQTY and WETH bridge balances to 1 WEI
        // This is not necessary but it makes the first claim cost
        // the same as the following ones
        deal(tokens["LQTY"].addr, address(bridge), 1);
        deal(tokens["WETH"].addr, address(bridge), 1);
    }

    function testInitialERC20Params() public {
        assertEq(bridge.name(), "StabilityPoolBridge");
        assertEq(bridge.symbol(), "SPB");
        assertEq(uint256(bridge.decimals()), 18);
    }

    function testIncorrectInput() public {
        // Call convert with incorrect input
        vm.prank(address(rollupProcessor));
        vm.expectRevert(StabilityPoolBridge.IncorrectInput.selector);
        bridge.convert(
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            0,
            0,
            0,
            address(0)
        );
    }

    function testFullDepositWithdrawalFlow() public {
        // I will deposit and withdraw 1 million LUSD
        uint256 depositAmount = 1e24;

        // 1. Mint the deposit amount of LUSD to the bridge
        deal(tokens["LUSD"].addr, address(rollupProcessor), depositAmount);

        // 2. Deposit LUSD to the StabilityPool contract through the bridge
        rollupProcessor.convert(
            address(bridge),
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            depositAmount,
            0,
            0
        );

        // 3. Check the total supply of SPB token is equal to the amount of LUSD deposited
        assertEq(bridge.totalSupply(), depositAmount);

        // 4. Check the SPB balance of rollupProcessor is equal to the amount of LUSD deposited
        assertEq(bridge.balanceOf(address(rollupProcessor)), depositAmount);

        // 5. Check the LUSD balance of the StabilityPoolBridge in the StabilityPool contract is equal to the amount
        // of LUSD deposited
        assertEq(bridge.STABILITY_POOL().getCompoundedLUSDDeposit(address(bridge)), depositAmount);

        // 6. withdrawAmount is equal to depositAmount because there were no rewards claimed -> LUSD/SPB ratio stayed 1
        uint256 withdrawAmount = depositAmount;

        // 8. Withdraw LUSD from StabilityPool through the bridge
        rollupProcessor.convert(
            address(bridge),
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            withdrawAmount,
            1,
            0
        );

        // 9. Check the total supply of SPB token is 0
        assertEq(bridge.totalSupply(), 0);

        // 10. Check the LUSD balance of rollupProcessor is equal to the initial LUSD deposit
        assertEq(tokens["LUSD"].erc.balanceOf(address(rollupProcessor)), depositAmount);
    }

    function testMultipleDepositsWithdrawals() public {
        uint256 i = 0;
        uint256 numIters = 2;
        uint256 depositAmount = 203;
        uint256[] memory spbBalances = new uint256[](numIters);

        while (i < numIters) {
            depositAmount = rand(depositAmount);
            // 1. Mint deposit amount of LUSD to the rollupProcessor
            deal(tokens["LUSD"].addr, address(rollupProcessor), depositAmount);
            // 2. Mint rewards to the bridge
            deal(tokens["LQTY"].addr, address(bridge), 1e20);
            deal(tokens["WETH"].addr, address(bridge), 1e18);

            // 3. Deposit LUSD to StabilityPool through the bridge
            (uint256 outputValueA, , ) = rollupProcessor.convert(
                address(bridge),
                AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
                AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
                AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
                AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
                depositAmount,
                i,
                0
            );

            spbBalances[i] = outputValueA;
            i++;
        }

        i = 0;
        while (i < numIters) {
            // 4. Withdraw LUSD from StabilityPool through the bridge
            rollupProcessor.convert(
                address(bridge),
                AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
                AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
                AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
                AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
                spbBalances[i],
                numIters + i,
                0
            );
            i++;
        }

        // 5. Check the total supply of SPB token is 0
        assertEq(bridge.totalSupply(), 0);
    }
}
