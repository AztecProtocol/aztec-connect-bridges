// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {TestUtil} from "./utils/TestUtil.sol";
import {StakingBridge} from "../../../bridges/liquity/StakingBridge.sol";

contract StakingBridgeUnitTest is TestUtil {
    AztecTypes.AztecAsset internal emptyAsset;
    StakingBridge private bridge;

    function setUp() public {
        _setUpTokensAndLabels();
        rollupProcessor = address(this);

        bridge = new StakingBridge(rollupProcessor);
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
        vm.expectRevert(ErrorLib.InvalidInput.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function testFullDepositWithdrawalFlow() public {
        // I will deposit and withdraw 1 million LQTY
        uint256 inputValue = 1e24;
        _deposit(inputValue);

        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset(
            2,
            address(bridge),
            AztecTypes.AztecAssetType.ERC20
        );
        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset(
            1,
            tokens["LQTY"].addr,
            AztecTypes.AztecAssetType.ERC20
        );

        // Transfer SB back to the bridge
        IERC20(inputAssetA.erc20Address).transfer(address(bridge), inputValue);

        // Withdraw LQTY from the staking contract through the bridge
        (uint256 outputValueA, , ) = bridge.convert(
            inputAssetA,
            emptyAsset,
            outputAssetA,
            emptyAsset,
            inputValue,
            1,
            0,
            address(0)
        );

        // Check the total supply of StakingBridge accounting token (SB) token is 0
        assertEq(bridge.totalSupply(), 0);

        // Transfer the funds back from the bridge to the rollup processor
        IERC20(outputAssetA.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueA);

        // Check the LQTY balance of rollupProcessor is greater than or equal to the initial LQTY deposit
        assertGe(outputValueA, inputValue);
    }

    function testMultipleDepositsWithdrawals(uint256[2] memory _depositAmounts) public {
        uint256 i = 0;
        uint256 numIters = 2;
        uint256[] memory sbBalances = new uint256[](numIters);

        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset(
            1,
            tokens["LQTY"].addr,
            AztecTypes.AztecAssetType.ERC20
        );
        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset(
            2,
            address(bridge),
            AztecTypes.AztecAssetType.ERC20
        );

        while (i < numIters) {
            uint256 depositAmount = bound(_depositAmounts[i], 1e18, 1e25);
            // 1. Mint deposit amount of LQTY directly to the bridge (to avoid transfer)
            deal(inputAssetA.erc20Address, address(bridge), depositAmount);
            // 2. Mint rewards to the bridge
            deal(tokens["LUSD"].addr, address(bridge), 1e20);
            deal(tokens["WETH"].addr, address(bridge), 1e18);

            // 3. Deposit LQTY to the staking contract through the bridge
            (uint256 outputValueA, , ) = bridge.convert(
                inputAssetA,
                emptyAsset,
                outputAssetA,
                emptyAsset,
                depositAmount,
                i,
                0,
                address(0)
            );

            // 4. Transfer SB back to RollupProcessor
            IERC20(outputAssetA.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueA);

            sbBalances[i] = outputValueA;
            i++;
        }

        // 5. Swap input/output assets to execute withdraw flow in the next convert call
        (inputAssetA, outputAssetA) = (outputAssetA, inputAssetA);

        i = 0;
        while (i < numIters) {
            uint256 inputValue = sbBalances[i];

            // 6. Transfer SB back to the bridge
            IERC20(inputAssetA.erc20Address).transfer(address(bridge), inputValue);

            // 7. Withdraw LQTY from staking contract through the bridge
            (uint256 outputValueA, , ) = bridge.convert(
                inputAssetA,
                emptyAsset,
                outputAssetA,
                emptyAsset,
                sbBalances[i],
                numIters + i,
                0,
                address(0)
            );

            // 8. Transfer LQTY back to RollupProcessor
            IERC20(outputAssetA.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueA);

            i++;
        }

        // 6. Check the total supply of SB token is 0
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
        vm.expectRevert(StakingBridge.SwapFailed.selector);
        bridge.convert(
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(1, tokens["LQTY"].addr, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
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
        vm.expectRevert(StakingBridge.SwapFailed.selector);
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
        vm.expectRevert(StakingBridge.SwapFailed.selector);
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
        deal(tokens["LQTY"].addr, address(bridge), _depositAmount);

        // 2. Deposit LQTY to the staking contract through the bridge
        (uint256 outputValueA, , ) = bridge.convert(
            AztecTypes.AztecAsset(1, tokens["LQTY"].addr, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            _depositAmount,
            0,
            0,
            address(0)
        );

        // 3. Check the total supply of SB token is equal to the amount of LQTY deposited
        assertEq(bridge.totalSupply(), _depositAmount);

        // 4. Transfer SB back to RollupProcessor
        IERC20(address(bridge)).transferFrom(address(bridge), rollupProcessor, outputValueA);

        // 5. Check the SB balance of rollupProcessor is equal to the amount of LQTY deposited
        assertEq(outputValueA, _depositAmount);
        assertEq(bridge.balanceOf(rollupProcessor), _depositAmount);

        // 6. Check the LQTY balance of StakingBridge in the staking contract is greater than or equal to the amount of
        // LQTY deposited
        assertGe(bridge.STAKING_CONTRACT().stakes(address(bridge)), _depositAmount);
    }
}
