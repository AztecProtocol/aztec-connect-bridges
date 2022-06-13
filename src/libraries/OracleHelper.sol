// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
pragma solidity >=0.8.4;

// TODO: move all the bridge imports to src/dependencies
import {IUniswapV3PoolDerivedState} from "../bridges/uniswapv3/interfaces/pool/IUniswapV3PoolDerivedState.sol";
import {TickMath} from "../bridges/uniswapv3/libraries/TickMath.sol";
import {FullMath} from "../bridges/uniswapv3/libraries/FullMath.sol";

// Code based on https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/OracleLibrary.sol
library OracleHelper {
    function _slippageToAmountOutMin(
        address _tokenIn,
        address _tokenOut,
        address _pool,
        uint256 _amountIn,
        int24 _slippageBps
    ) internal view returns (uint256 amountOutMinimum) {
        // 1st get arithmetic mean tick for the last 10 minutes
        uint256 secondsAgo = 600; // 10 * 60 = 10 minutes
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = uint32(secondsAgo);
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, ) = IUniswapV3PoolDerivedState(_pool).observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 arithmeticMeanTick = int24(tickCumulativesDelta / int256(secondsAgo));
        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int256(secondsAgo) != 0)) arithmeticMeanTick--;

        // 2nd drop/rise the tick by a given bips amount
        bool tokenOrder = _tokenIn < _tokenOut;
        // Compute tick after slippage and based on that compute the ratio
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(
            tokenOrder ? arithmeticMeanTick - _slippageBps : arithmeticMeanTick + _slippageBps
        );

        // Calculate quoteAmount at the modified tick
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            amountOutMinimum = tokenOrder
                ? FullMath.mulDiv(ratioX192, _amountIn, 1 << 192)
                : FullMath.mulDiv(1 << 192, _amountIn, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            amountOutMinimum = tokenOrder
                ? FullMath.mulDiv(ratioX128, _amountIn, 1 << 128)
                : FullMath.mulDiv(1 << 128, _amountIn, ratioX128);
        }
    }
}
