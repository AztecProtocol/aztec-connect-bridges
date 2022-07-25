// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWETH} from "../interfaces/IWETH.sol";
import {BytesLib} from "../libraries/uniswapv3/BytesLib.sol";
import {FullMath} from "../libraries/uniswapv3/FullMath.sol";
import {TickMath} from "../libraries/uniswapv3/TickMath.sol";
import {OracleLibrary} from "../libraries/uniswapv3/OracleLibrary.sol";
import {IUniswapV3Factory} from "../interfaces/uniswapv3/IUniswapV3Factory.sol";
import {IUniswapV3PoolState} from "../interfaces/uniswapv3/pool/IUniswapV3PoolState.sol";
import {IQuoter} from "../interfaces/uniswapv3/IQuoter.sol";
import {ISwapRouter} from "../interfaces/uniswapv3/ISwapRouter.sol";

import {IPathRegistry} from "./interfaces/IPathRegistry.sol";

// @inheritdoc IPathRegistry
contract PathRegistry is IPathRegistry {
    using BytesLib for bytes;

    IUniswapV3Factory public constant uniswapV3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    IQuoter public constant QUOTER_V3 = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    ISwapRouter public constant ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    struct Path {
        uint248 amount; // Amount at which the path starts being valid
        uint8 next; // Index of the next path
        address ethPool; // Eth pool to fetch based on which to convert the gas cost to tokenOut
        SubPath[] subPaths;
    }

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
    function registerPath(
        SubPath[] calldata _subPaths,
        uint248 _amount,
        uint24 _feeTier
    ) external override {
        (address tokenIn, address tokenOut) = _getTokenInOut(_subPaths[0].path);
        uint256 curPathIndex = firstPathIndices[tokenIn][tokenOut];
        Path memory newPath = Path(_amount, uint8(0), _getEthPool(tokenOut, _feeTier), _subPaths);
        Path memory curPath = allPaths[curPathIndex];

        if (curPathIndex == 0) {
            if (_evaluatePath(newPath, newPath.amount, tokenOut) == 0) revert UnviablePath();

            allPaths.push(newPath);
            firstPathIndices[tokenIn][tokenOut] = allPaths.length - 1;

            if (!IERC20(tokenIn).approve(address(ROUTER), type(uint256).max)) revert ApproveFailed();
        } else if (newPath.amount < curPath.amount) {
            // New path should be inserted before the first path
            // Check whether newPath is better than the current first path at newPath.amount
            if (_evaluatePath(curPath, newPath.amount, tokenOut) >= _evaluatePath(newPath, newPath.amount, tokenOut))
                revert QuoteNotBetter();
            if (_evaluatePath(curPath, curPath.amount, tokenOut) < _evaluatePath(newPath, curPath.amount, tokenOut)) {
                // newPath is better even at curPath.amount - replace curPath with newPath
                allPaths[curPathIndex] = newPath;
                allPaths[curPathIndex].next = curPath.next;
                // I didn't put the condition inside prunePaths to avoid 1 SLOAD
                if (curPath.next != 0) _prunePaths(curPathIndex, tokenOut);
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
            if (_evaluatePath(curPath, newPath.amount, tokenOut) >= _evaluatePath(newPath, newPath.amount, tokenOut))
                revert QuoteNotBetter();

            if (
                curPath.next != 0 &&
                _evaluatePath(newPath, nextPath.amount, tokenOut) > _evaluatePath(nextPath, nextPath.amount, tokenOut)
            ) {
                // newPath is better than nextPath at nextPath.amount - save newPath at nextPath index
                allPaths[curPath.next] = newPath;
                allPaths[curPath.next].next = nextPath.next;
                // I didn't put the condition inside prunePaths to avoid 1 SLOAD
                if (nextPath.next != 0) _prunePaths(curPath.next, tokenOut);
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
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn,
        uint256 _amountOutMin
    ) external payable returns (uint256 amountOut) {
        uint256 curPathIndex = firstPathIndices[_tokenIn][_tokenOut];
        if (curPathIndex == 0) revert PathNotInitialized();

        // 1. Convert ETH to WETH or transfer ERC20 to address(this)
        if (msg.value > 0) {
            if (_tokenIn != WETH) revert NonWethInput();
            if (msg.value != _amountIn) revert IncorrectAmountIn();
            IWETH(WETH).deposit{value: msg.value}();
        } else {
            if (!IERC20(_tokenIn).transferFrom(msg.sender, address(this), _amountIn)) revert TransferFailed();
        }

        // 2. Find the swap path - iterate through the tokenIn-tokenOut linked list and select the first path whose
        // next path doesn't exist or next path's amount is bigger than amountIn
        Path memory path = allPaths[curPathIndex];
        Path memory nextPath = allPaths[path.next];
        while (path.next != 0 && _amountIn >= nextPath.amount) {
            path = nextPath;
            nextPath = allPaths[path.next];
        }

        // 3. Swap
        uint256 subAmountIn;
        uint256 arrayLength = path.subPaths.length;
        for (uint256 i; i < arrayLength; ) {
            SubPath memory subPath = path.subPaths[i];
            subAmountIn = (_amountIn * subPath.percent) / 100;
            amountOut += ROUTER.exactInput(
                ISwapRouter.ExactInputParams(subPath.path, msg.sender, block.timestamp, subAmountIn, 0)
            );
            unchecked {
                ++i;
            }
        }

        if (amountOut < _amountOutMin) revert InsufficientAmountOut({received: amountOut, required: _amountOutMin});
    }

    // @inheritdoc IPathRegistry
    function quote(
        address _tokenIn,
        address _tokenOut,
        uint256 _amountIn
    ) external returns (uint256 amountOut) {
        uint256 curPathIndex = firstPathIndices[_tokenIn][_tokenOut];
        if (curPathIndex == 0) revert PathNotInitialized();

        // 1. Find the swap path - iterate through the tokenIn-tokenOut linked list and select the first path whose
        // next path doesn't exist or next path's amount is bigger than amountIn
        Path memory path = allPaths[curPathIndex];
        Path memory nextPath = allPaths[path.next];
        while (path.next != 0 && _amountIn >= nextPath.amount) {
            path = nextPath;
            nextPath = allPaths[path.next];
        }

        // Get quote
        uint256 subAmountIn;
        uint256 arrayLength = path.subPaths.length;
        for (uint256 i; i < arrayLength; ) {
            SubPath memory subPath = path.subPaths[i];
            subAmountIn = (_amountIn * subPath.percent) / 100;
            amountOut += QUOTER_V3.quoteExactInput(subPath.path, subAmountIn);
            unchecked {
                ++i;
            }
        }
    }

    /**
     * @notice Compares a given path with the following ones and if the following paths are worse deletes them
     * @param _pathIndex An index of a path which will be compared with the paths that follow
     * @param _tokenOut An address of tokenOut (@dev This param is redundant because it could be extracted from
     * the path itself. I keep the param here in order to save gas.)
     * @dev This method was implemented in order to keep the amount of stored paths low - this is very desirable
     * because paths are being iterated through during swap
     */
    function _prunePaths(uint256 _pathIndex, address _tokenOut) private {
        Path memory path = allPaths[_pathIndex];
        Path memory nextPath = allPaths[path.next];

        while (_evaluatePath(nextPath, nextPath.amount, _tokenOut) <= _evaluatePath(path, nextPath.amount, _tokenOut)) {
            delete allPaths[path.next];
            path.next = nextPath.next;
            allPaths[_pathIndex].next = nextPath.next;
            nextPath = allPaths[path.next];
        }
    }

    /**
     * @notice Evaluates quality of a given path for `amountIn`
     * @param _path A path to evaluate
     * @param _amountIn An amount of tokenIn to get a quote for
     * @param _tokenOut An address of tokenOut (@dev This param is redundant because it could be extracted from
     * the path itself. I keep the param here in order to save gas.)
     * @return score An integer measuring a quality of a path (higher is better)
     * @dev This method takes into consideration quote and gas consumed
     */
    function _evaluatePath(
        Path memory _path,
        uint256 _amountIn,
        address _tokenOut
    ) private returns (uint256 score) {
        uint256 subAmountIn;
        uint256 percentSum;

        uint256 gasLeftBefore = gasleft();
        uint256 arrayLength = _path.subPaths.length;
        for (uint256 i; i < arrayLength; ) {
            SubPath memory subPath = _path.subPaths[i];
            subAmountIn = (_amountIn * subPath.percent) / 100;
            score += QUOTER_V3.quoteExactInput(subPath.path, subAmountIn);
            percentSum += subPath.percent;
            unchecked {
                ++i;
            }
        }
        // Note: this value does not precisely represent gas consumed during swaps since swaps are not exactly equal
        // to quoting. However it should be a good enough approximation.
        uint256 weiConsumed = (gasLeftBefore - gasleft()) * tx.gasprice;
        uint256 tokenConsumed = _getQuoteAtCurrentTick(weiConsumed, _tokenOut);
        score = (score > tokenConsumed) ? score - tokenConsumed : 0;

        if (percentSum != 100) revert IncorrectPercSum();
    }

    function _getEthPool(address _tokenOut, uint24 _feeTier) private view returns (address pool) {
        pool = uniswapV3Factory.getPool(WETH, _tokenOut, _feeTier);
        if (pool == address(0)) revert NonExistentEthPool();
    }

    /// @notice Fetches current tick from a WETH-quoteToken pool and calls getQuoteAtTick(...)
    function _getQuoteAtCurrentTick(uint256 _weiAmount, address _tokenOut) private view returns (uint256 quoteAmount) {
        address poolAddr = uniswapV3Factory.getPool(WETH, _tokenOut, 3000);
        IUniswapV3PoolState pool = IUniswapV3PoolState(poolAddr);
        (, int24 currentTick, , , , , ) = pool.slot0();
        quoteAmount = OracleLibrary.getQuoteAtTick(currentTick, uint128(_weiAmount), WETH, _tokenOut);
    }

    /**
     * @notice Returns input and output token from a multihop path
     * @param _path A path in a fromat of that used in unisweap router.
     * @return tokenIn Addresses of the first token in the path (input token)
     * @return tokenOut Addresses of the last token in the path (output token)
     */
    function _getTokenInOut(bytes _path) private pure returns (address tokenIn, address tokenOut) {
        tokenIn = _path.toAddress(0);
        tokenOut = _path.toAddress(_path.length - 20);
    }
}
