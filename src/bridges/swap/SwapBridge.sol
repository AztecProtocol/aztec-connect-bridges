// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {ISwapRouter} from "../../interfaces/uniswapv3/ISwapRouter.sol";
import {IWETH} from "../../interfaces/IWETH.sol";

/**
 * @title Aztec Connect Bridge for swapping on Uniswap v3
 * @author Jan Benes (@benesjan on Github and Telegram)
 * @notice You can use this contract to swap tokens on Uniswap v3 along complex paths.
 * @dev Encoding of a path allows for up to 2 split paths and up to 3 pools (2 middle tokens) in a each split path.
 *      A path is encoded in _auxData parameter passed to the convert method. _auxData carry 64 bits of information.
 *      Along with split paths there is a minimum price encoded in the auxData.
 *
 *      Each split path takes 19 bits. Minimum price is encoded in 26 bits. Values are placed in the data as follows:
 *          |26 bits minimum price| |19 bits split path 2| |19 bits split path 1|
 *
 *      Encoding of split path is:
 *          |7 bits percentage| |2 bits fee| |3 bits middle token| |2 bits fee| |3 bits middle token| |2 bits fee|
 *      The meaning of percentage is how much of input amount will be routed through the corresponding split path.
 *      Fee bits are mapped to specific fee tiers as follows:
 *          00 is 0.01%, 01 is 0.05%, 10 is 0.3%, 11 is 1%
 *      Middle tokens use the following mapping:
 *          001 is ETH, 010 is USDC, 011 is USDT, 100 is DAI, 101 is WBTC, 110 is FRAX, 111 is BUSD.
 *          000 means the middle token is unused.
 *
 *      Min price is encoded as a floating point number. First 21 bits are used for significand, last 5 bits for
 *      exponent: |21 bits significand| |5 bits exponent|
 *      Minimum amount out is computed with the following formula:
 *          (inputValue * (significand * 10**exponent)) / (10 ** outputAssetDecimals)
 */
contract SwapBridge is BridgeBase {
    error InvalidFeeTierEncoding();
    error InvalidTokenEncoding();
    error InvalidPercentageAmounts();
    error InsufficientAmountOut();

    // @notice A struct representing a path with 2 split paths.
    struct Path {
        uint256 percentage1; // Percentage of input to swap through splitPath1
        bytes splitPath1; // A path encoded in a format used by Uniswap's v3 router
        uint256 percentage2; // Percentage of input to swap through splitPath2
        bytes splitPath2; // A path encoded in a format used by Uniswap's v3 router
        uint256 minPrice; // Minimum acceptable price
    }

    // @dev Event which is emitted when the output token doesn't implement decimals().
    event DefaultDecimalsWarning(address token);

    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    ISwapRouter public constant UNI_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    uint64 private constant SPLIT_PATH_BIT_LENGTH = 19;
    uint64 private constant SPLIT_PATHS_BIT_LENGTH = 38; // SPLIT_PATH_BIT_LENGTH * 2
    uint64 private constant PRICE_BIT_LENGTH = 26; // 64 - SPLIT_PATHS_BIT_LENGTH

    // @dev The following masks are used to decode 2 split paths and minimum acceptable price from 1 uint64.
    // Binary number 0000000000000000000000000000000000000000000001111111111111111111 (last 19 bits)
    uint64 private constant SPLIT_PATH_MASK = 0x7FFFF;

    // Binary number 0000000000000000000000000000000000000011111111111111111111111111 (last 26 bits)
    uint64 private constant PRICE_MASK = 0x3FFFFFF;

    // Binary number 0000000000000000000000000000000000000000000000000000000000011111 (last 5 bits)
    uint64 private constant EXPONENT_MASK = 0x1F;

    // Binary number 11
    uint64 private constant FEE_MASK = 0x3;
    // Binary number 111
    uint64 private constant TOKEN_MASK = 0x7;

    /**
     * @notice Set the address of rollup processor.
     * @param _rollupProcessor Address of rollup processor
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    receive() external payable {}

    /**
     * @notice Sets all the important approvals.
     * @param _tokenIn - Address of input token to later swap in convert(...) function
     * @param _tokenOut - Address of output token to later return to rollup processor
     * @dev SwapBridge never holds any ERC20 tokens after or before an invocation of any of its functions. For this
     * reason the following is not a security risk and makes convert(...) function more gas efficient.
     * @dev Note: If any of the input or output tokens is ETH just pass in a 0 address.
     */
    function preApproveTokenPair(address _tokenIn, address _tokenOut) external {
        if (_tokenIn != address(0)) {
            // Input token not ETH
            if (!IERC20(_tokenIn).approve(address(UNI_ROUTER), type(uint256).max)) {
                revert ErrorLib.ApproveFailed(_tokenIn);
            }
        }
        if (_tokenOut != address(0)) {
            // Output token not ETH
            if (!IERC20(_tokenOut).approve(address(ROLLUP_PROCESSOR), type(uint256).max)) {
                revert ErrorLib.ApproveFailed(_tokenOut);
            }
        }
    }

    /**
     * @notice A function which swaps input token for output token along the path encoded in _auxData.
     * @param _inputAssetA - Input ERC20 token
     * @param _outputAssetA - Output ERC20 token
     * @param _inputValue - Amount of input token to swap
     * @param _interactionNonce - Interaction nonce
     * @param _auxData - Encoded path (gets decoded to Path struct)
     * @return outputValueA - The amount of output token received
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64 _auxData,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256,
            bool
        )
    {
        bool inputIsEth = _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH;
        bool outputIsEth = _outputAssetA.assetType == AztecTypes.AztecAssetType.ETH;

        if (_inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20 && !inputIsEth) {
            revert ErrorLib.InvalidInputA();
        }
        if (_outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20 && !outputIsEth) {
            revert ErrorLib.InvalidOutputA();
        }

        Path memory path = _decodePath(
            inputIsEth ? WETH : _inputAssetA.erc20Address,
            _auxData,
            outputIsEth ? WETH : _outputAssetA.erc20Address
        );

        uint256 inputValueSplitPath1 = (_inputValue * path.percentage1) / 100;

        outputValueA = UNI_ROUTER.exactInput{value: inputIsEth ? inputValueSplitPath1 : 0}(
            ISwapRouter.ExactInputParams({
                path: path.splitPath1,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: inputValueSplitPath1,
                amountOutMinimum: 0
            })
        );

        if (path.percentage2 != 0) {
            uint256 inputValueSplitPath2 = _inputValue - inputValueSplitPath1;
            outputValueA += UNI_ROUTER.exactInput{value: inputIsEth ? inputValueSplitPath2 : 0}(
                ISwapRouter.ExactInputParams({
                    path: path.splitPath2,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: inputValueSplitPath2,
                    amountOutMinimum: 0
                })
            );
        }

        uint256 tokenOutDecimals = 18;
        if (!outputIsEth) {
            try IERC20Metadata(_outputAssetA.erc20Address).decimals() returns (uint8 decimals) {
                tokenOutDecimals = decimals;
            } catch (bytes memory) {
                emit DefaultDecimalsWarning(_outputAssetA.erc20Address);
            }
        }
        uint256 amountOutMinimum = (_inputValue * path.minPrice) / 10**tokenOutDecimals;

        if (outputValueA < amountOutMinimum) revert InsufficientAmountOut();

        if (outputIsEth) {
            IWETH(WETH).withdraw(outputValueA);
            IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(_interactionNonce);
        }
    }

    function _decodePath(
        address _tokenIn,
        uint64 _encodedPath,
        address _tokenOut
    ) internal view returns (Path memory path) {
        (uint256 percentage1, bytes memory splitPath1) = _decodeSplitPath(
            _tokenIn,
            _encodedPath & SPLIT_PATH_MASK,
            _tokenOut
        );
        path.percentage1 = percentage1;
        path.splitPath1 = splitPath1;

        (uint256 percentage2, bytes memory splitPath2) = _decodeSplitPath(
            _tokenIn,
            (_encodedPath >> SPLIT_PATH_BIT_LENGTH) & SPLIT_PATH_MASK,
            _tokenOut
        );

        if (percentage1 + percentage2 != 100) revert InvalidPercentageAmounts();

        path.percentage2 = percentage2;
        path.splitPath2 = splitPath2;
        path.minPrice = _decodeMinPrice(_encodedPath >> SPLIT_PATHS_BIT_LENGTH);
    }

    function _decodeSplitPath(
        address _tokenIn,
        uint64 _encodedSplitPath,
        address _tokenOut
    ) internal view returns (uint256 percentage, bytes memory path) {
        uint64 fee3 = _encodedSplitPath & FEE_MASK;
        uint64 middleToken2 = (_encodedSplitPath >> 2) & TOKEN_MASK;
        uint64 fee2 = (_encodedSplitPath >> 5) & FEE_MASK;
        uint64 middleToken1 = (_encodedSplitPath >> 7) & TOKEN_MASK;
        uint64 fee1 = (_encodedSplitPath >> 10) & FEE_MASK;
        percentage = _encodedSplitPath >> 12;

        if (middleToken1 != 0 && middleToken2 != 0) {
            path = abi.encodePacked(
                _tokenIn,
                _getFeeTier(fee1),
                _getMiddleToken(middleToken1),
                _getFeeTier(fee2),
                _getMiddleToken(middleToken2),
                _getFeeTier(fee3),
                _tokenOut
            );
        } else if (middleToken1 != 0) {
            path = abi.encodePacked(
                _tokenIn,
                _getFeeTier(fee1),
                _getMiddleToken(middleToken1),
                _getFeeTier(fee3),
                _tokenOut
            );
        } else if (middleToken2 != 0) {
            path = abi.encodePacked(
                _tokenIn,
                _getFeeTier(fee2),
                _getMiddleToken(middleToken2),
                _getFeeTier(fee3),
                _tokenOut
            );
        } else {
            path = abi.encodePacked(_tokenIn, _getFeeTier(fee3), _tokenOut);
        }
    }

    function _decodeMinPrice(uint64 _encodedMinPrice) internal pure returns (uint256 minPrice) {
        // 21 bits significand, 5 bits exponent
        uint64 significand = _encodedMinPrice >> 5;
        uint64 exponent = _encodedMinPrice & EXPONENT_MASK;
        minPrice = significand * 10**exponent;
    }

    function _getFeeTier(uint64 _encodedFeeTier) internal pure returns (uint24 feeTier) {
        if (_encodedFeeTier == 0) {
            // Binary number 00
            return uint24(100);
        }
        if (_encodedFeeTier == 1) {
            // Binary number 01
            return uint24(500);
        }
        if (_encodedFeeTier == 2) {
            // Binary number 10
            return uint24(3000);
        }
        if (_encodedFeeTier == 3) {
            // Binary number 11
            return uint24(10000);
        }
        revert InvalidFeeTierEncoding();
    }

    function _getMiddleToken(uint256 _encodedToken) internal pure returns (address token) {
        if (_encodedToken == 1) {
            // ETH, binary number 001
            return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        }
        if (_encodedToken == 2) {
            // USDC, binary number 010
            return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        }
        if (_encodedToken == 3) {
            // USDT, binary number 011
            return 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        }
        if (_encodedToken == 4) {
            // DAI, binary number 100
            return 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        }
        if (_encodedToken == 5) {
            // WBTC, binary number 101
            return 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        }
        if (_encodedToken == 6) {
            // FRAX, binary number 110
            return 0x853d955aCEf822Db058eb8505911ED77F175b99e;
        }
        if (_encodedToken == 7) {
            // BUSD, binary number 111
            return 0x4Fabb145d64652a948d72533023f6E7A623C7C53;
        }
        revert InvalidTokenEncoding();
    }
}
