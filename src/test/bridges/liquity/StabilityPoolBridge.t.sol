// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {TestUtil} from "./utils/TestUtil.sol";
import {StabilityPoolBridge} from "../../../bridges/liquity/StabilityPoolBridge.sol";

contract StabilityPoolBridgeTest is TestUtil {
    StabilityPoolBridge private bridge;

    function setUp() public {
        _aztecPreSetup();
        setUpTokens();

        bridge = new StabilityPoolBridge(address(rollupProcessor), address(0));
        bridge.setApprovals();

        // EIP-1087 optimization related mints
        // Note: For LQTY and LUSD the optimization would work even without
        // this mint after the first rewards are claimed. This is not the case
        // for LUSD.
        deal(tokens["LUSD"].addr, address(bridge), 1);
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
        // I will deposit and withdraw 1 million LUSD
        uint256 lusdAmount = 1e24;
        _deposit(lusdAmount);

        // Withdraw LUSD from StabilityPool through the bridge
        rollupProcessor.convert(
            address(bridge),
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            lusdAmount,
            1,
            0
        );

        // Check the total supply of SPB token is 0
        assertEq(bridge.totalSupply(), 0);

        // Check the LUSD balance of rollupProcessor is equal to the initial LUSD deposit
        assertEq(tokens["LUSD"].erc.balanceOf(address(rollupProcessor)), lusdAmount);
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

    function _deposit(uint256 _depositAmount) private {
        // 1. Mint the deposit amount of LUSD to the bridge
        deal(tokens["LUSD"].addr, address(rollupProcessor), _depositAmount);

        // 2. Deposit LUSD to the StabilityPool contract through the bridge
        rollupProcessor.convert(
            address(bridge),
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            _depositAmount,
            0,
            0
        );

        // 3. Check the total supply of SPB token is equal to the amount of LUSD deposited
        assertEq(bridge.totalSupply(), _depositAmount);

        // 4. Check the SPB balance of rollupProcessor is equal to the amount of LUSD deposited
        assertEq(bridge.balanceOf(address(rollupProcessor)), _depositAmount);

        // 5. Check the LUSD balance of the StabilityPoolBridge in the StabilityPool contract is equal to the amount
        // of LUSD deposited
        assertEq(bridge.STABILITY_POOL().getCompoundedLUSDDeposit(address(bridge)), _depositAmount);
    }
}
