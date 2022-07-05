// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {TestUtil} from "./utils/TestUtil.sol";
import {StabilityPoolBridge} from "../../../bridges/liquity/StabilityPoolBridge.sol";

contract StabilityPoolBridgeUnitTest is TestUtil {
    address public constant LQTY_ETH_POOL = 0xD1D5A4c0eA98971894772Dcd6D2f1dc71083C44E; // 3000 bps fee tier
    address public constant USDC_ETH_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640; // 500 bps fee tier
    address public constant LUSD_USDC_POOL = 0x4e0924d3a751bE199C426d52fb1f2337fa96f736; // 500 bps fee tier

    StabilityPoolBridge private bridge;

    function setUp() public {
        rollupProcessor = address(this);
        setUpTokens();

        bridge = new StabilityPoolBridge(rollupProcessor, address(0));
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
        vm.expectRevert(ErrorLib.InvalidInput.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function testFullDepositWithdrawalFlow() public {
        // I will deposit and withdraw 1 million LUSD
        uint256 inputValue = 1e24;
        _deposit(inputValue);

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

        // Transfer SPB back to the bridge
        IERC20(inputAssetA.erc20Address).transfer(address(bridge), inputValue);

        // Withdraw LUSD from StabilityPool through the bridge
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

        // Check the total supply of SPB token is 0
        assertEq(bridge.totalSupply(), 0);

        // Transfer the funds back from the bridge to the rollup processor
        IERC20(outputAssetA.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueA);

        // Check the LUSD balance of rollupProcessor is greater or equal to the initial LUSD deposit
        assertGe(outputValueA, inputValue);
    }

    function testMultipleDepositsWithdrawals() public {
        uint256 i = 0;
        uint256 numIters = 2;
        uint256 depositAmount = 203;
        uint256[] memory spbBalances = new uint256[](numIters);

        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset(
            1,
            tokens["LUSD"].addr,
            AztecTypes.AztecAssetType.ERC20
        );
        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset(
            2,
            address(bridge),
            AztecTypes.AztecAssetType.ERC20
        );

        while (i < numIters) {
            depositAmount = rand(depositAmount);
            // 1. Mint deposit amount of LUSD to the directly to the bridge (to avoid transfer)
            deal(inputAssetA.erc20Address, address(bridge), depositAmount);
            // 2. Mint rewards to the bridge
            deal(tokens["LQTY"].addr, address(bridge), 1e20);
            deal(tokens["WETH"].addr, address(bridge), 1e18);

            // 3. Deposit LUSD to StabilityPool through the bridge
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

            // 4. Transfer SPB back to RollupProcessor
            IERC20(outputAssetA.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueA);

            spbBalances[i] = outputValueA;
            i++;
        }

        // 5. Swap input/output assets to execute withdraw flow in the next convert call
        (inputAssetA, outputAssetA) = (outputAssetA, inputAssetA);

        i = 0;
        while (i < numIters) {
            uint256 inputValue = spbBalances[i];

            // 6. Transfer SPB back to the bridge
            IERC20(inputAssetA.erc20Address).transfer(address(bridge), inputValue);

            // 7. Withdraw LUSD from StabilityPool through the bridge
            (uint256 outputValueA, , ) = bridge.convert(
                inputAssetA,
                emptyAsset,
                outputAssetA,
                emptyAsset,
                inputValue,
                numIters + i,
                0,
                address(0)
            );

            // 4. Transfer LUSD back to RollupProcessor
            IERC20(outputAssetA.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueA);

            i++;
        }

        // 5. Check the total supply of SPB token is 0
        assertEq(bridge.totalSupply(), 0);
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

    function testUrgentModeOffSwap2Q() public {
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

    function _deposit(uint256 _depositAmount) private {
        // 1. Mint the deposit amount of LUSD to the bridge
        deal(tokens["LUSD"].addr, address(bridge), _depositAmount);

        // 2. Deposit LUSD to the StabilityPool contract through the bridge
        (uint256 outputValueA, , ) = bridge.convert(
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
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
    }
}
