// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {AztecTypes} from "../../aztec/AztecTypes.sol";

import {TestUtil} from "./utils/TestUtil.sol";
import {StakingBridge} from "../../bridges/liquity/StakingBridge.sol";

contract StakingBridgeTest is TestUtil {
    StakingBridge private bridge;

    function setUp() public {
        _aztecPreSetup();
        setUpTokens();
        bridge = new StakingBridge(address(rollupProcessor));
        bridge.setApprovals();

        // Set LQTY bridge balance to 1 WEI
        // Necessary for the optimization based on EIP-1087 to work!
        deal(tokens["LQTY"].addr, address(bridge), 1);
    }

    function testInitialERC20Params() public {
        assertEq(bridge.name(), "StakingBridge");
        assertEq(bridge.symbol(), "SB");
        assertEq(uint256(bridge.decimals()), 18);
    }

    function testIncorrectInput() public {
        // Call convert with incorrect input
        vm.prank(address(rollupProcessor));
        vm.expectRevert(StakingBridge.IncorrectInput.selector);
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
        // I will deposit and withdraw 1 million LQTY
        uint256 depositAmount = 1e24;

        // 1. Mint the deposit amount of LQTY to the bridge
        deal(tokens["LQTY"].addr, address(rollupProcessor), depositAmount);

        // 2. Deposit LQTY to the staking contract through the bridge
        rollupProcessor.convert(
            address(bridge),
            AztecTypes.AztecAsset(1, tokens["LQTY"].addr, AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            depositAmount,
            0,
            0
        );

        // 3. Check the total supply of SB token is equal to the amount of LQTY deposited
        assertEq(bridge.totalSupply(), depositAmount);

        // 4. Check the SB balance of rollupProcessor is equal to the amount of LQTY deposited
        assertEq(bridge.balanceOf(address(rollupProcessor)), depositAmount);

        // 5. Check the LQTY balance of StakingBridge in the staking contract is equal to the amount of LQTY deposited
        assertEq(bridge.STAKING_CONTRACT().stakes(address(bridge)), depositAmount);

        // 6. withdrawAmount is equal to depositAmount because there were no rewards claimed -> LQTY/SB ratio stayed 1
        uint256 withdrawAmount = depositAmount;

        // 7. Withdraw LQTY from the staking contract through the bridge
        rollupProcessor.convert(
            address(bridge),
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(1, tokens["LQTY"].addr, AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            withdrawAmount,
            1,
            0
        );

        // 8. Check the total supply of SPB token is 0
        assertEq(bridge.totalSupply(), 0);

        // 9. Check the LQTY balance of rollupProcessor is equal to the initial LQTY deposit
        assertEq(tokens["LQTY"].erc.balanceOf(address(rollupProcessor)), depositAmount);
    }

    function testMultipleDepositsWithdrawals() public {
        uint256 i = 0;
        uint256 numIters = 2;
        uint256 depositAmount = 203;
        uint256[] memory sbBalances = new uint256[](numIters);

        while (i < numIters) {
            depositAmount = rand(depositAmount);
            // 1. Mint deposit amount of LQTY to the rollupProcessor
            deal(tokens["LQTY"].addr, address(rollupProcessor), depositAmount);
            // 2. Mint rewards to the bridge
            deal(tokens["LUSD"].addr, address(bridge), 1e20);
            deal(tokens["WETH"].addr, address(bridge), 1e18);

            // 3. Deposit LQTY to the staking contract through the bridge
            (uint256 outputValueA, , ) = rollupProcessor.convert(
                address(bridge),
                AztecTypes.AztecAsset(1, tokens["LQTY"].addr, AztecTypes.AztecAssetType.ERC20),
                AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
                AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
                AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
                depositAmount,
                i,
                0
            );

            sbBalances[i] = outputValueA;
            i++;
        }

        i = 0;
        while (i < numIters) {
            // 4. Withdraw LQTY from Staking through the bridge
            rollupProcessor.convert(
                address(bridge),
                AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
                AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
                AztecTypes.AztecAsset(1, tokens["LQTY"].addr, AztecTypes.AztecAssetType.ERC20),
                AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
                sbBalances[i],
                numIters + i,
                0
            );
            i++;
        }

        // 6. Check the total supply of SPB token is 0
        assertEq(bridge.totalSupply(), 0);
    }
}
