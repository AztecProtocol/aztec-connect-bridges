// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
pragma solidity >=0.8.4;

import {FullMath} from "../../libraries/uniswapv3/FullMath.sol";
import {TickMath} from "../../libraries/uniswapv3/TickMath.sol";
import {OracleLibrary} from "../../libraries/uniswapv3/OracleLibrary.sol";
import {IUniswapV3Factory} from "../../interfaces/uniswapv3/IUniswapV3Factory.sol";
import {IUniswapV3PoolState} from "../../interfaces/uniswapv3/pool/IUniswapV3PoolState.sol";

/// @title Pieces of code from OracleLib.sol, TickMath.sol and FullMath.sol ported to solidity ^0.8.0
library PathRegistryLib {
    /// @dev The maximum tick that may be passed to #getSqrtRatioAtTick computed from log base 1.0001 of 2**128
    address internal constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    IUniswapV3Factory internal constant uniswapV3Factory =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    function ethPoolExists(address quoteToken) internal view returns (bool poolExists) {
        poolExists = uniswapV3Factory.getPool(WETH, quoteToken, 3000) != address(0);
    }

    /// @notice Fetches current tick from a WETH-quoteToken pool and calls getQuoteAtTick(...)
    function getQuoteAtCurrentTick(uint256 weiAmount, address quoteToken) internal view returns (uint256 quoteAmount) {
        address poolAddr = uniswapV3Factory.getPool(WETH, quoteToken, 3000);
        IUniswapV3PoolState pool = IUniswapV3PoolState(poolAddr);
        (, int24 currentTick, , , , , ) = pool.slot0();
        quoteAmount = OracleLibrary.getQuoteAtTick(currentTick, uint128(weiAmount), WETH, quoteToken);
    }
}
