// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {TestUtil} from "./utils/TestUtil.sol";
import {StabilityPoolBridge} from "../../../bridges/liquity/StabilityPoolBridge.sol";

contract StabilityPoolBridgeUnitTest is TestUtil {
    AztecTypes.AztecAsset internal emptyAsset;
    StabilityPoolBridge private bridge;

    function setUp() public {
        _setUpTokensAndLabels();
        rollupProcessor = address(this);

        bridge = new StabilityPoolBridge(rollupProcessor, address(0));
        bridge.setApprovals();

        // EIP-1087 optimization related mints
        // Note: For LQTY and LUSD the optimization would work even without
        // this mint after the first rewards are claimed. This is not the case
        // for LUSD.
        deal(tokens["LUSD"].addr, address(bridge), 1);
        deal(tokens["LQTY"].addr, address(bridge), 1);
        deal(tokens["WETH"].addr, address(bridge), 1);

        // Reset ETH balance to 0 to make accounting easier
        deal(address(bridge), 0);
    }

    function testInitialERC20Params() public {
        assertEq(bridge.name(), "StabilityPoolBridge");
        assertEq(bridge.symbol(), "SPB");
        assertEq(uint256(bridge.decimals()), 18);
    }

    function testIncorrectInput() public {
        // Call convert with incorrect input
        vm.expectRevert(ErrorLib.InvalidInput.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function testFullDepositWithdrawalFlow(
        uint96 _depositAmount,
        uint96 _withdrawalAmount,
        uint64 _ethRewards,
        uint72 _lqtyRewards
    ) public {
        uint256 depositAmount = bound(_depositAmount, 10, type(uint96).max);
        uint256 spbReceived = _deposit(depositAmount);

        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset(
            2,
            address(bridge),
            AztecTypes.AztecAssetType.ERC20
        );
        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset(
            1,
            tokens["LUSD"].addr,
            AztecTypes.AztecAssetType.ERC20
        );

        // Transfer StabilityPoolBridge accounting token (SPB) back to the bridge
        IERC20(inputAssetA.erc20Address).transfer(address(bridge), spbReceived);

        // Mint rewards to the bridge
        deal(address(bridge), _ethRewards);
        deal(tokens["LQTY"].addr, address(bridge), _lqtyRewards);

        // Withdraw LUSD from StabilityPool through the bridge
        uint256 withdrawalAmount = bound(_withdrawalAmount, 10, spbReceived);

        (uint256 outputValueA, , ) = bridge.convert(
            inputAssetA,
            emptyAsset,
            outputAssetA,
            emptyAsset,
            withdrawalAmount,
            1,
            0,
            address(0)
        );

        // Check the total supply of SPB token is spbReceived - withdrawalAmount
        assertEq(bridge.totalSupply(), spbReceived - withdrawalAmount);

        // Transfer the funds back from the bridge to the rollup processor
        assertTrue(
            IERC20(outputAssetA.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueA),
            "Transfer failed"
        );
    }

    function testUrgentModeOffSwap1() public {
        // I will deposit and withdraw 1 million LUSD
        uint256 lusdAmount = 1e24;
        _deposit(lusdAmount);

        // Mint rewards to the bridge
        deal(tokens["LQTY"].addr, address(bridge), 1e21);
        deal(tokens["WETH"].addr, address(bridge), 1e18);

        // Destroy the pools reserves in order for the swap to fail
        deal(tokens["WETH"].addr, LQTY_ETH_POOL, 0);

        // Withdraw LUSD from StabilityPool through the bridge
        vm.expectRevert(StabilityPoolBridge.SwapFailed.selector);
        bridge.convert(
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            lusdAmount,
            1,
            0,
            address(0)
        );
    }

    function testUrgentModeOffSwap2() public {
        // I will deposit and withdraw 1 million LUSD
        uint256 lusdAmount = 1e24;
        _deposit(lusdAmount);

        // Mint rewards to the bridge
        deal(tokens["LQTY"].addr, address(bridge), 1e21);
        deal(tokens["WETH"].addr, address(bridge), 1e18);

        // Destroy the pools reserves in order for the swap to fail
        deal(tokens["USDC"].addr, USDC_ETH_POOL, 0);

        // Withdraw LUSD from StabilityPool through the bridge
        vm.expectRevert(StabilityPoolBridge.SwapFailed.selector);
        bridge.convert(
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            lusdAmount,
            1,
            0,
            address(0)
        );
    }

    function testUrgentModeOffSwap3() public {
        // I will deposit and withdraw 1 million LUSD
        uint256 lusdAmount = 1e24;
        _deposit(lusdAmount);

        // Mint rewards to the bridge
        deal(tokens["LQTY"].addr, address(bridge), 1e21);
        deal(tokens["WETH"].addr, address(bridge), 1e18);

        // Destroy the pools reserves in order for the swap to fail
        deal(tokens["LUSD"].addr, LUSD_USDC_POOL, 0);

        // Withdraw LUSD from StabilityPool through the bridge
        vm.expectRevert(StabilityPoolBridge.SwapFailed.selector);
        bridge.convert(
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            lusdAmount,
            1,
            0,
            address(0)
        );
    }

    function _deposit(uint256 _depositAmount) private returns (uint256) {
        // 1. Mint the deposit amount of LUSD to the bridge
        deal(tokens["LUSD"].addr, address(bridge), _depositAmount);

        // 2. Deposit LUSD to the StabilityPool contract through the bridge
        (uint256 outputValueA, , ) = bridge.convert(
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            _depositAmount,
            0,
            0,
            address(0)
        );

        // 3. Check the total supply of SPB token is equal to the amount of LUSD deposited
        assertEq(bridge.totalSupply(), _depositAmount);

        // 4. Transfer SPB back to RollupProcessor
        IERC20(address(bridge)).transferFrom(address(bridge), rollupProcessor, outputValueA);

        // 5. Check the SPB balance of rollupProcessor is equal to the amount of LUSD deposited
        assertEq(outputValueA, _depositAmount);
        assertEq(bridge.balanceOf(rollupProcessor), _depositAmount);

        // 6. Check the LUSD balance of the StabilityPoolBridge in the StabilityPool contract is greater than or equal
        // to the amount of LUSD deposited
        assertGe(bridge.STABILITY_POOL().getCompoundedLUSDDeposit(address(bridge)), _depositAmount);

        return outputValueA;
    }
}
