// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {TestUtil} from "./utils/TestUtil.sol";
import {StakingBridge} from "../../../bridges/liquity/StakingBridge.sol";

contract StakingBridgeTest is TestUtil {
    address public constant LUSD_USDC_POOL = 0x4e0924d3a751bE199C426d52fb1f2337fa96f736; // 500 bps fee tier
    address public constant USDC_ETH_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640; // 500 bps fee tier
    address public constant LQTY_ETH_POOL = 0xD1D5A4c0eA98971894772Dcd6D2f1dc71083C44E; // 3000 bps fee tier

    StakingBridge private bridge;

    function setUp() public {
        _aztecPreSetup();
        setUpTokens();
        bridge = new StakingBridge(address(rollupProcessor));
        bridge.setApprovals();

        // EIP-1087 optimization related mints
        // Note: For LUSD and WETH the optimization would work even without
        // this mint after the first rewards are claimed. This is not the case
        // for LQTY.
        deal(tokens["LQTY"].addr, address(bridge), 1);
        deal(tokens["LUSD"].addr, address(bridge), 1);
        deal(tokens["WETH"].addr, address(bridge), 1);
    }

    function testInitialERC20Params() public {
        assertEq(bridge.name(), "StakingBridge");
        assertEq(bridge.symbol(), "SB");
        assertEq(uint256(bridge.decimals()), 18);
    }

    function testIncorrectInput() public {
        // Call convert with incorrect input
        vm.prank(address(rollupProcessor));
        vm.expectRevert(ErrorLib.InvalidInput.selector);
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
        uint256 lqtyAmount = 1e24;
        _deposit(lqtyAmount);

        // Withdraw LQTY from the staking contract through the bridge
        rollupProcessor.convert(
            address(bridge),
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(1, tokens["LQTY"].addr, AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            lqtyAmount,
            1,
            0
        );

        // Check the total supply of SPB token is 0
        assertEq(bridge.totalSupply(), 0);

        // Check the LQTY balance of rollupProcessor is equal to the initial LQTY deposit
        assertEq(tokens["LQTY"].erc.balanceOf(address(rollupProcessor)), lqtyAmount);
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

    function testUrgentModeOffSwap1() public {
        // I will deposit and withdraw 1 million LQTY
        uint256 lqtyAmount = 1e24;
        _deposit(lqtyAmount);

        // Mint rewards to the bridge
        deal(tokens["LUSD"].addr, address(bridge), 1e21);
        deal(tokens["WETH"].addr, address(bridge), 1e18);

        // Destroy the pools reserves in order for the following swap to fail
        deal(bridge.USDC(), LUSD_USDC_POOL, 0);

        // Withdraw LQTY from the staking contract through the bridge
        vm.expectRevert(ErrorLib.SwapFailed.selector);
        vm.prank(address(rollupProcessor));
        bridge.convert(
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(1, tokens["LQTY"].addr, AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            lqtyAmount,
            1,
            0,
            address(0)
        );
    }

    function testUrgentModeOffSwap2() public {
        // I will deposit and withdraw 1 million LQTY
        uint256 lqtyAmount = 1e24;
        _deposit(lqtyAmount);

        // Mint rewards to the bridge
        deal(tokens["LUSD"].addr, address(bridge), 1e21);
        deal(tokens["WETH"].addr, address(bridge), 1e18);

        // Destroy the pools reserves in order for the following swap to fail
        deal(tokens["WETH"].addr, USDC_ETH_POOL, 0);

        // Withdraw LQTY from the staking contract through the bridge
        vm.expectRevert(ErrorLib.SwapFailed.selector);
        vm.prank(address(rollupProcessor));
        bridge.convert(
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(1, tokens["LQTY"].addr, AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            lqtyAmount,
            1,
            0,
            address(0)
        );
    }

    function testUrgentModeOffSwap3() public {
        // I will deposit and withdraw 1 million LQTY
        uint256 lqtyAmount = 1e24;
        _deposit(lqtyAmount);

        // Mint rewards to the bridge
        deal(tokens["LUSD"].addr, address(bridge), 1e21);
        deal(tokens["WETH"].addr, address(bridge), 1e18);

        // Destroy the pools reserves in order for the following swap to fail
        deal(tokens["LQTY"].addr, LQTY_ETH_POOL, 0);

        // Withdraw LQTY from the staking contract through the bridge
        vm.expectRevert(ErrorLib.SwapFailed.selector);
        vm.prank(address(rollupProcessor));
        bridge.convert(
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(1, tokens["LQTY"].addr, AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            lqtyAmount,
            1,
            0,
            address(0)
        );
    }

    function _deposit(uint256 _depositAmount) private {
        // 1. Mint the deposit amount of LQTY to the bridge
        deal(tokens["LQTY"].addr, address(rollupProcessor), _depositAmount);

        // 2. Deposit LQTY to the staking contract through the bridge
        rollupProcessor.convert(
            address(bridge),
            AztecTypes.AztecAsset(1, tokens["LQTY"].addr, AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            _depositAmount,
            0,
            0
        );

        // 3. Check the total supply of SB token is equal to the amount of LQTY deposited
        assertEq(bridge.totalSupply(), _depositAmount);

        // 4. Check the SB balance of rollupProcessor is equal to the amount of LQTY deposited
        assertEq(bridge.balanceOf(address(rollupProcessor)), _depositAmount);

        // 5. Check the LQTY balance of StakingBridge in the staking contract is equal to the amount of LQTY deposited
        assertEq(bridge.STAKING_CONTRACT().stakes(address(bridge)), _depositAmount);
    }
}
