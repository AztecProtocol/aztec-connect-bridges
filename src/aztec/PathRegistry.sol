// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {BytesLib} from "../libraries/uniswapv3/BytesLib.sol";
import {IQuoter} from "../interfaces/uniswapv3/IQuoter.sol";
// TODO: point to ../interfaces/uniswapv3 once the liquity audit feedback is merged
import {ISwapRouter} from "../interfaces/liquity/ISwapRouter.sol";

import {IPathRegistry} from "./interfaces/IPathRegistry.sol";
import {PathRegistryLib} from "./libraries/PathRegistryLib.sol";

// @inheritdoc IPathRegistry
contract PathRegistry is IPathRegistry {
    using BytesLib for bytes;

    IQuoter public constant QUOTER_V3 = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    ISwapRouter public constant ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    // @dev A mapping containing indices of the smallest amount paths
    mapping(address => mapping(address => uint256)) public firstPathIndices;

    // @dev An array used to store all the paths
    Path[] public allPaths;

    error NonExistentEthPool();
    error UnviablePath();
    error ApproveFailed();
    error QuoteNotBetter();
    error PathNotInitialized();
    error NonWethInput();
    error IncorrectAmountIn();
    error TransferFailed();
    error InsufficientAmountOut(uint256 received, uint256 required);
    error IncorrectPercSum();
    error EmptyPath();

    constructor() {
        // Waste the first array element in order to be able to check uninitialized Path by index == 0
        allPaths.push();
    }

    // @inheritdoc IPathRegistry
    function registerPath(Path calldata newPath) external override {
        (address tokenIn, address tokenOut) = getTokenInOut(newPath);
        uint256 curPathIndex = firstPathIndices[tokenIn][tokenOut];
        Path memory curPath = allPaths[curPathIndex];

        if (curPathIndex == 0) {
            if (!PathRegistryLib.ethPoolExists(tokenOut)) revert NonExistentEthPool();
            if (evaluatePath(newPath, newPath.amount, tokenOut) == 0) revert UnviablePath();

            allPaths.push(newPath);
            firstPathIndices[tokenIn][tokenOut] = allPaths.length - 1;

            if (!IERC20(tokenIn).approve(address(ROUTER), type(uint256).max)) revert ApproveFailed();
        } else if (newPath.amount < curPath.amount) {
            // New path should be inserted before the first path
            // Check whether newPath is better than the current first path at newPath.amount
            if (evaluatePath(curPath, newPath.amount, tokenOut) >= evaluatePath(newPath, newPath.amount, tokenOut))
                revert QuoteNotBetter();
            if (evaluatePath(curPath, curPath.amount, tokenOut) < evaluatePath(newPath, curPath.amount, tokenOut)) {
                // newPath is better even at curPath.amount - replace curPath with newPath
                allPaths[curPathIndex] = newPath;
                allPaths[curPathIndex].next = curPath.next;
                // I didn't put the condition inside prunePaths to avoid 1 SLOAD
                if (curPath.next != 0) prunePaths(curPathIndex, tokenOut);
            } else {
                // newPath is worse at curPath.amount - insert the path at the first position
                allPaths.push(newPath);
                uint256 pathIndex = allPaths.length - 1;
                allPaths[pathIndex].next = curPathIndex;
                firstPathIndices[tokenIn][tokenOut] = pathIndex;
            }
        } else {
            // Since newPath.amount > curPath.amount the path will not be inserted at the first position and for this
            // reason we have compute where the new path should be inserted
            Path memory nextPath = allPaths[curPath.next];
            while (curPath.next != 0 && newPath.amount > nextPath.amount) {
                curPathIndex = curPath.next;
                curPath = nextPath;
                nextPath = allPaths[curPath.next];
            }

            // Verify that newPath's quote is better at newPath.amount than prevPath's
            if (evaluatePath(curPath, newPath.amount, tokenOut) >= evaluatePath(newPath, newPath.amount, tokenOut))
                revert QuoteNotBetter();

            if (
                curPath.next != 0 &&
                evaluatePath(newPath, nextPath.amount, tokenOut) > evaluatePath(nextPath, nextPath.amount, tokenOut)
            ) {
                // newPath is better than nextPath at nextPath.amount - save newPath at nextPath index
                allPaths[curPath.next] = newPath;
                allPaths[curPath.next].next = nextPath.next;
                // I didn't put the condition inside prunePaths to avoid 1 SLOAD
                if (nextPath.next != 0) prunePaths(curPath.next, tokenOut);
            } else {
                // Insert new path between prevPath and nextPath
                allPaths.push(newPath);
                uint256 newPathIndex = allPaths.length - 1;
                allPaths[curPathIndex].next = newPathIndex;
                allPaths[newPathIndex].next = curPath.next;
            }
        }
    }

    // @inheritdoc IPathRegistry
    function swap(
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) external payable returns (uint256 amountOut) {
        uint256 curPathIndex = firstPathIndices[tokenIn][tokenOut];
        if (curPathIndex == 0) revert PathNotInitialized();

        // 1. Convert ETH to WETH or transfer ERC20 to address(this)
        if (msg.value > 0) {
            if (tokenIn != WETH) revert NonWethInput();
            if (msg.value != amountIn) revert IncorrectAmountIn();
            IWETH(WETH).deposit{value: msg.value}();
        } else {
            if (!IERC20(tokenIn).transferFrom(msg.sender, address(this), amountIn)) revert TransferFailed();
        }

        // 2. Find the swap path - iterate through the tokenIn-tokenOut linked list and select the first path whose
        // next path doesn't exist or next path's amount is bigger than amountIn
        Path memory path = allPaths[curPathIndex];
        Path memory nextPath = allPaths[path.next];
        while (path.next != 0 && amountIn >= nextPath.amount) {
            path = nextPath;
            nextPath = allPaths[path.next];
        }

        // 3. Swap
        uint256 subAmountIn;
        uint256 arrayLength = path.subPaths.length;
        for (uint256 i; i < arrayLength; ) {
            SubPath memory subPath = path.subPaths[i];
            subAmountIn = (amountIn * subPath.percent) / 100;
            amountOut += ROUTER.exactInput(
                ISwapRouter.ExactInputParams(subPath.path, msg.sender, block.timestamp, subAmountIn, 0)
            );
            unchecked {
                ++i;
            }
        }

        if (amountOut < amountOutMin) revert InsufficientAmountOut({received: amountOut, required: amountOutMin});
    }

    // @inheritdoc IPathRegistry
    function quote(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) external returns (uint256 amountOut) {
        uint256 curPathIndex = firstPathIndices[tokenIn][tokenOut];
        if (curPathIndex == 0) revert PathNotInitialized();

        // 1. Find the swap path - iterate through the tokenIn-tokenOut linked list and select the first path whose
        // next path doesn't exist or next path's amount is bigger than amountIn
        Path memory path = allPaths[curPathIndex];
        Path memory nextPath = allPaths[path.next];
        while (path.next != 0 && amountIn >= nextPath.amount) {
            path = nextPath;
            nextPath = allPaths[path.next];
        }

        // Get quote
        uint256 subAmountIn;
        uint256 arrayLength = path.subPaths.length;
        for (uint256 i; i < arrayLength; ) {
            SubPath memory subPath = path.subPaths[i];
            subAmountIn = (amountIn * subPath.percent) / 100;
            amountOut += QUOTER_V3.quoteExactInput(subPath.path, subAmountIn);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Compares a given path with the following ones and if the following paths are worse deletes them
     * @param pathIndex An index of a path which will be compared with the paths that follow
     * @param tokenOut An address of tokenOut (@dev This param is redundant because it could be extracted from
     * the path itself. I keep the param here in order to save gas.)
     * @dev This method was implemented in order to keep the amount of stored paths low - this is very desirable
     * because paths are being iterated through during swap
     */
    function prunePaths(uint256 pathIndex, address tokenOut) private {
        Path memory path = allPaths[pathIndex];
        Path memory nextPath = allPaths[path.next];

        while (evaluatePath(nextPath, nextPath.amount, tokenOut) <= evaluatePath(path, nextPath.amount, tokenOut)) {
            delete allPaths[path.next];
            path.next = nextPath.next;
            allPaths[pathIndex].next = nextPath.next;
            nextPath = allPaths[path.next];
        }
    }

    /**
     * @notice Evaluates quality of a given path for `amountIn`
     * @param path A path to evaluate
     * @param amountIn An amount of tokenIn to get a quote for
     * @param tokenOut An address of tokenOut (@dev This param is redundant because it could be extracted from
     * the path itself. I keep the param here in order to save gas.)
     * @return score An integer measuring a quality of a path (higher is better)
     * @dev This method takes into consideration quote and gas consumed
     */
    function evaluatePath(
        Path memory path,
        uint256 amountIn,
        address tokenOut
    ) private returns (uint256 score) {
        uint256 subAmountIn;
        uint256 percentSum;

        uint256 gasLeftBefore = gasleft();
        uint256 arrayLength = path.subPaths.length;
        for (uint256 i; i < arrayLength; ) {
            SubPath memory subPath = path.subPaths[i];
            subAmountIn = (amountIn * subPath.percent) / 100;
            score += QUOTER_V3.quoteExactInput(subPath.path, subAmountIn);
            percentSum += subPath.percent;
            unchecked {
                ++i;
            }
        }
        // Note: this value does not precisely represent gas consumed during swaps since swaps are not exactly equal
        // to quoting. However it should be a good enough approximation.
        uint256 weiConsumed = (gasLeftBefore - gasleft()) * tx.gasprice;
        // TODO: replace the following by calling Mean Finance's static oracle once the oracle is deployed
        uint256 tokenConsumed = PathRegistryLib.getQuoteAtCurrentTick(weiConsumed, tokenOut);
        score = (score > tokenConsumed) ? score - tokenConsumed : 0;

        if (percentSum != 100) revert IncorrectPercSum();
    }

    /**
     * @notice Returns input and output token from a multihop path
     * @param path A path from which the input and output token will be extracted
     * @return tokenIn Addresses of the first token in the path (input token)
     * @return tokenOut Addresses of the last token in the path (output token)
     */
    function getTokenInOut(Path memory path) private pure returns (address tokenIn, address tokenOut) {
        if (path.subPaths.length != 0) {
            bytes memory v3Path = path.subPaths[0].path;
            tokenIn = v3Path.toAddress(0);
            tokenOut = v3Path.toAddress(v3Path.length - 20);
        } else {
            revert EmptyPath();
        }
    }
}
