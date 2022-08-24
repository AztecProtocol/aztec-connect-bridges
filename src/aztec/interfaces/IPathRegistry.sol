// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
pragma solidity >=0.8.4;

/**
 * @title A contract allowing for registration of paths and token swapping on Uniswap v2 and v3
 * @author Jan Benes (@benesjan on Github and Telegram)
 * @notice You can use this contract to register a path and then to swap tokens using the registered paths
 * @dev This smart contract has 2 functions:
 *      1. A registration and a quality verification of Uniswap v2 and v3 paths
 *      2. Swapping tokens using the registered paths - a path is selected based on the input and output token addresses
 *         and the amount of input token to swap
 *
 *      For each registered tokenIn-tokenOut pair there is a linked list of Path structs sorted by amount in
 *      an ascending order. This linked list can be iterated through using the next parameter. Each path is valid
 *      in a range [path.amount, nextPath.amount). If path.next doesn't exist, the path is valid
 *      in [path.amount, infinity).
 */
interface IPathRegistry {
    struct SubPath {
        uint256 percent;
        bytes path;
    }

    /**
     * @notice Verifies and registers a new path
     * @param _subPaths An array of subpaths
     * @param _amount Amount at which the path gets used
     * @param _feeTier A Fee tier identifying which ETH-tokenOut pool to use for gas cost conversion
     * @dev Reverts when the new path doesn't have a better quote than the previous path at newPath.amount or when
     *      Uniswap v3 ETH-tokenOut 3000 BIPS fee pool doesn't exist (this pool is needed for gas intensity evaluation).
     */
    function registerPath(
        SubPath[] calldata _subPaths,
        uint232 _amount,
        uint24 _feeTier
    ) external;

    /**
     * @notice Selects a path based on `tokenIn`, `tokenOut` and `amountIn` and swaps `amountIn` of `tokenIn` for
     * as much as possible of `tokenOut` along the selected path
     * @param _tokenIn An address of a token to sell
     * @param _tokenOut An address of a token to buy
     * @param _amountIn An amount of `tokenIn` to swap
     * @param _amountOutMin Minimum amount of tokenOut to receive (inactive when set to 0)
     * @return amountOut An amount of token received
     * @dev Reverts when a path is not found
     */
    function swap(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOutMin
    ) external payable returns (uint256 amountOut);

    /**
     * @notice Selects a path based on `tokenIn`, `tokenOut` and `amountIn` and computes a quote for `amountIn`
     * @param _tokenIn An address of a token to sell
     * @param _tokenOut An address of a token to buy
     * @param _amountIn An amount of `tokenIn` to get a quote for
     * @return amountOut An amount of token received
     * @dev Reverts when a path is not found. Not marked as view because Uni v3 quoter modifies states and then reverts.
     */
    function quote(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external returns (uint256 amountOut);
}
