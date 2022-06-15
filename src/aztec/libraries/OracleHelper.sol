// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
pragma solidity >=0.8.4;

import {IUniswapV3PoolDerivedState} from "../../interfaces/uniswapv3/pool/IUniswapV3PoolDerivedState.sol";
import {TickMath} from "../../libraries/uniswapv3/TickMath.sol";
import {FullMath} from "../../libraries/uniswapv3/FullMath.sol";

// Code based on https://github.com/Uniswap/v3-periphery/blob/main/contracts/libraries/OracleLibrary.sol
library OracleHelper {
    error IncorrectInput(int24 slippageBps);

    uint256 internal constant TWAP_SECONDS = 600; // 10 * 60 = 10 minutes

    /**
     * @notice A function which converts input amount and a slippage denominated in BPS to minimum output amount.
     * @param _tokenIn - Address of the input token
     * @param _tokenOut - Address of the output token
     * @param _pool - Address of the Uniswap v3 pool
     * @param _slippageBps - Maximum acceptable slippage denominated in BPS
     * @return amountOutMinimum - Minimum acceptable amount of tokenOut
     * @dev If 'OLD' error is thrown in the Uniswap Oracle library, increase the amount of observations by calling
     *      IUniswapV3PoolActions(_pool).increaseObservationCardinalityNext(numberOfObservation)
     */
    function slippageToAmountOutMin(
        address _tokenIn,
        address _tokenOut,
        address _pool,
        uint256 _amountIn,
        int24 _slippageBps
    ) internal view returns (uint256 amountOutMinimum) {
        if (_slippageBps < 10 || _slippageBps > 2000) revert IncorrectInput(_slippageBps);

        // 1st get arithmetic mean tick for the last 10 minutes
        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = uint32(TWAP_SECONDS);
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, ) = IUniswapV3PoolDerivedState(_pool).observe(secondsAgos);

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 arithmeticMeanTick = int24(tickCumulativesDelta / int256(TWAP_SECONDS));
        // Always round to negative infinity
        if (tickCumulativesDelta < 0 && (tickCumulativesDelta % int256(TWAP_SECONDS) != 0)) arithmeticMeanTick--;

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
