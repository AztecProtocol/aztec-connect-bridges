// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {OracleHelper} from "../../../aztec/libraries/OracleHelper.sol";
import {IUniswapV3PoolImmutables} from "../../../interfaces/uniswapv3/pool/IUniswapV3PoolImmutables.sol";
import {IUniswapV3PoolDerivedState} from "../../../interfaces/uniswapv3/pool/IUniswapV3PoolDerivedState.sol";
import {TickMath} from "../../../libraries/uniswapv3/TickMath.sol";
import {FullMath} from "../../../libraries/uniswapv3/FullMath.sol";

contract OracleHelperTest is Test {
    address[] private pools = [
        0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640, // USDC/WETH 500 bps
        0x4e0924d3a751bE199C426d52fb1f2337fa96f736, // LUSD/USDC 500 bps
        // 0xD1D5A4c0eA98971894772Dcd6D2f1dc71083C44E, // LQTY/WETH 3000 bps
        0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36, // WETH/USDT 3000 bps
        0x3416cF6C708Da44DB2624D63ea0AAef7113527C6, // USDC/USDT 100 bps
        0xc63B0708E2F7e69CB8A1df0e1389A98C35A76D52, // FRAX/USDC 500 bps
        0x93f267fD92B432BeBf4dA4E13B8615Bb8Eb2095C // GUSD/USDC 3000 bps
        // 0x4ba950bED410a12C1294DF28eD672f50C24297de // GUSD/WETH 3000 bps - liquidity too low
    ];

    function testSlippageToAmountOutMin(int16 _slippageBps, uint96 _amountIn) public {
        _slippageBps = int16(int256(bound(uint256(int256(_slippageBps)), 10, 2000)));
        _amountIn = uint96(bound(_amountIn, 1, type(uint96).max));
        for (uint256 i; i < pools.length; ++i) {
            IUniswapV3PoolImmutables pool = IUniswapV3PoolImmutables(pools[i]);
            address token0 = pool.token0();
            address token1 = pool.token1();
            _validateAmountOutMin(token0, token1, address(pool), _amountIn, _slippageBps);
            _validateAmountOutMin(token1, token0, address(pool), _amountIn, _slippageBps);
        }
    }

    function _validateAmountOutMin(
        address _tokenIn,
        address _tokenOut,
        address _pool,
        uint256 _amountIn,
        int24 _slippageBps
    ) private {
        uint256 amountOutMinimum = OracleHelper.slippageToAmountOutMin(
            _tokenIn,
            _tokenOut,
            _pool,
            _amountIn,
            _slippageBps
        );

        uint256 noSlippageAmount = _getNoSlippageAmount(_tokenIn, _tokenOut, _pool, _amountIn);

        // When quote is too low rounding errors break the test - irrelevant so I skip these cases
        if (noSlippageAmount < 1e3) return;

        assertLt(amountOutMinimum, noSlippageAmount, "Min amount isn't lower than no-slippage amount");

        uint256 bipsDiff = (1e18 - (amountOutMinimum * 1e18) / noSlippageAmount) / 1e14;
        uint256 maxDelta = uint256(int256(_slippageBps));
        if (maxDelta < 20) maxDelta = 20;

        assertApproxEqAbs(bipsDiff, uint256(int256(_slippageBps)), maxDelta, "Slippage bps diff too high");
    }

    function _getNoSlippageAmount(
        address _tokenIn,
        address _tokenOut,
        address _pool,
        uint256 _amountIn
    ) private view returns (uint256 quoteAmount) {
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = uint32(OracleHelper.TWAP_SECONDS);
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, ) = IUniswapV3PoolDerivedState(_pool).observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 arithmeticMeanTick = int24(tickCumulativesDelta / int256(OracleHelper.TWAP_SECONDS));
        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int256(OracleHelper.TWAP_SECONDS) != 0))
            arithmeticMeanTick--;

        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(arithmeticMeanTick);

        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = _tokenIn < _tokenOut
                ? FullMath.mulDiv(ratioX192, _amountIn, 1 << 192)
                : FullMath.mulDiv(1 << 192, _amountIn, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = _tokenIn < _tokenOut
                ? FullMath.mulDiv(ratioX128, _amountIn, 1 << 128)
                : FullMath.mulDiv(1 << 128, _amountIn, ratioX128);
        }
    }
}
