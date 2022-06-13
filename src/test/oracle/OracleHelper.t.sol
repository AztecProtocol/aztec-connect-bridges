// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {OracleHelper} from "../../libraries/OracleHelper.sol";

contract OracleHelperTest is Test {
    address public constant USDC_WETH_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    function testBipsToMinAmountWETHToUSDC(int8 _slippageBps, uint96 _amountIn) public {
        vm.assume(_slippageBps >= 1 && _slippageBps <= 100 && _amountIn > 1e12);
        address tokenIn = WETH;
        address tokenOut = USDC;

        uint256 amountOutMinimum = OracleHelper._slippageToAmountOutMin(
            tokenIn,
            tokenOut,
            USDC_WETH_POOL,
            _amountIn,
            _slippageBps
        );

        uint256 noSlippageAmount = OracleHelper._slippageToAmountOutMin(
            tokenIn,
            tokenOut,
            USDC_WETH_POOL,
            _amountIn,
            0
        );
        assertLt(amountOutMinimum, noSlippageAmount, "Min amount isn't lower than no-slippapge amount");

        uint256 bipsDiff = (1e12 - (amountOutMinimum * 1e12) / noSlippageAmount) / 1e8;
        assertApproxEqAbs(bipsDiff, uint256(int256(_slippageBps)), 14, "Slippage bps diff too high");
    }

    function testBipsToMinAmountUSDCToWETH(int8 _slippageBps, uint96 _amountIn) public {
        vm.assume(_slippageBps >= 1 && _slippageBps <= 100 && _amountIn > 0);
        address tokenIn = USDC;
        address tokenOut = WETH;

        uint256 amountOutMinimum = OracleHelper._slippageToAmountOutMin(
            tokenIn,
            tokenOut,
            USDC_WETH_POOL,
            _amountIn,
            _slippageBps
        );

        uint256 noSlippageAmount = OracleHelper._slippageToAmountOutMin(
            tokenIn,
            tokenOut,
            USDC_WETH_POOL,
            _amountIn,
            0
        );
        assertLt(amountOutMinimum, noSlippageAmount, "Min amount isn't lower than no-slippapge amount");

        uint256 bipsDiff = (1e12 - (amountOutMinimum * 1e12) / noSlippageAmount) / 1e8;
        assertApproxEqAbs(bipsDiff, uint256(int256(_slippageBps)), 14, "Slippage dps diff too high");
    }
}
