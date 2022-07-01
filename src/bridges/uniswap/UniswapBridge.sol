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
 * @dev Encoding of a path allows for up to 2 split paths (see the definition bellow) and up to 3 pools (2 middle
 *      tokens) in a each split path. A path is encoded in _auxData parameter passed to the convert method. _auxData
 *      carry 64 bits of information. Along with split paths there is a minimum price encoded in auxData.
 *
 *      Each split path takes 19 bits. Minimum price is encoded in 26 bits. Values are placed in the data as follows:
 *          |26 bits minimum price| |19 bits split path 2| |19 bits split path 1|
 *
 *      Encoding of a split path is:
 *          |7 bits percentage| |2 bits fee| |3 bits middle token| |2 bits fee| |3 bits middle token| |2 bits fee|
 *      The meaning of percentage is how much of input amount will be routed through the corresponding split path.
 *      Fee bits are mapped to specific fee tiers as follows:
 *          00 is 0.01%, 01 is 0.05%, 10 is 0.3%, 11 is 1%
 *      Middle tokens use the following mapping:
 *          001 is ETH, 010 is USDC, 011 is USDT, 100 is DAI, 101 is WBTC, 110 is FRAX, 111 is BUSD.
 *          000 means the middle token is unused.
 *
 *      To compute a minimum price we can simply divide amountOutMinimum with input amount (swap amount). Minimum price
 *      is expected to be encoded as a floating point number. First 21 bits are used for significand, last 5 bits for
 *      exponent:
 *          |21 bits significand| |5 bits exponent|
 *      To convert minimum price to this format call encodeMinPrice(...) function on this contract.
 *
 *      Minimum price is converted back to integer using the following formula:
 *          minPriceInt = significand * 10**exponent,
 *      to get amountOutMinimum we simply multiply the value from above with input amount:
 *          amountOutMinimum = minPriceInt * _inputValue
 *
 *      Definition of split path: Split path is a term we use when there are multiple (in this case 2) paths between
 *      which the input amount of tokens is split. As an example we can consider swapping 100 ETH to DAI. In this case
 *      there could be 2 split paths. 1st split path going through ETH-USDC 500 bps fee pool and USDC-DAI 100 bps fee
 *      pool and 2nd split path going directly to DAI using the ETH-DAI 500 bps pool. First split path could for
 *      example consume 80% of input (80 ETH) and the second split path the remaining 20% (20 ETH).
 */
contract UniswapBridge is BridgeBase {
    error InvalidFeeTierEncoding();
    error InvalidFeeTier();
    error InvalidTokenEncoding();
    error InvalidToken();
    error InvalidPercentageAmounts();
    error InsufficientAmountOut();
    error Overflow();

    // @notice A struct representing a path with 2 split paths.
    struct Path {
        uint256 percentage1; // Percentage of input to swap through splitPath1
        bytes splitPath1; // A path encoded in a format used by Uniswap's v3 router
        uint256 percentage2; // Percentage of input to swap through splitPath2
        bytes splitPath2; // A path encoded in a format used by Uniswap's v3 router
        uint256 minPrice; // Minimum acceptable price
    }

    ISwapRouter public constant UNI_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    // Addresses of middle tokens
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant FRAX = 0x853d955aCEf822Db058eb8505911ED77F175b99e;
    address public constant BUSD = 0x4Fabb145d64652a948d72533023f6E7A623C7C53;

    uint64 public constant SPLIT_PATH_BIT_LENGTH = 19;
    uint64 public constant SPLIT_PATHS_BIT_LENGTH = 38; // SPLIT_PATH_BIT_LENGTH * 2
    uint64 public constant PRICE_BIT_LENGTH = 26; // 64 - SPLIT_PATHS_BIT_LENGTH

    // @dev The following masks are used to decode 2 split paths and minimum acceptable price from 1 uint64.
    // Binary number 0000000000000000000000000000000000000000000001111111111111111111 (last 19 bits)
    uint64 public constant SPLIT_PATH_MASK = 0x7FFFF;

    // Binary number 0000000000000000000000000000000000000011111111111111111111111111 (last 26 bits)
    uint64 public constant PRICE_MASK = 0x3FFFFFF;

    // Binary number 0000000000000000000000000000000000000000000000000000000000011111 (last 5 bits)
    uint64 public constant EXPONENT_MASK = 0x1F;

    // Binary number 11
    uint64 public constant FEE_MASK = 0x3;
    // Binary number 111
    uint64 public constant TOKEN_MASK = 0x7;

    /**
     * @notice Set the address of rollup processor.
     * @param _rollupProcessor Address of rollup processor
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    // @dev Empty method which is present here in order to be able to receive ETH when unwrapping WETH.
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

        if (path.percentage1 != 0) {
            // Swap using the first swap path
            outputValueA = UNI_ROUTER.exactInput{value: inputIsEth ? inputValueSplitPath1 : 0}(
                ISwapRouter.ExactInputParams({
                    path: path.splitPath1,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: inputValueSplitPath1,
                    amountOutMinimum: 0
                })
            );
        }

        if (path.percentage2 != 0) {
            // Swap using the second swap path
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

        if (outputValueA < _inputValue * path.minPrice) revert InsufficientAmountOut();
        if (outputIsEth) {
            IWETH(WETH).withdraw(outputValueA);
            IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(_interactionNonce);
        }
    }

    /**
     * @notice A function which encodes min price to the format used in this bridge.
     * @param _minPrice - Minimum acceptable price
     * @return encodedMinPrice - Min acceptable encoded in a format used in this bridge.
     * @dev This function is not optimized and is expected to be used on frontend and in tests.
     * @dev Reverts when _minPrice is bigger than max encodeable value.
     */
    function encodeMinPrice(uint256 _minPrice) external pure returns (uint256 encodedMinPrice) {
        // 2097151 = 2**21 --> this number and its multiples of 10 can be encoded without precision loss
        if (_minPrice <= 2097151) {
            // uintValue is smaller than the boundary of significand --> significand = _x, exponent = 0
            encodedMinPrice = _minPrice << 5;
        } else {
            uint256 exponent = 0;
            while (_minPrice > 2097151) {
                _minPrice /= 10;
                ++exponent;
                // 31 = 2**5 - 1 --> max exponent
                if (exponent > 31) revert Overflow();
            }
            encodedMinPrice = (_minPrice << 5) + exponent;
        }
    }

    /**
     * @notice A function which encodes a split path.
     * @param _percentage - Percentage of swap amount to send through this split path
     * @param _fee1 - 1st pool fee
     * @param _token1 - Address of the 1st pool's output token
     * @param _fee2 - 2nd pool fee
     * @param _token2 - Address of the 2nd pool's output token
     * @param _fee3 - 3rd pool fee
     * @return Encoded split path (in the last 19 bits of uint)
     * @dev In place of unused middle tokens and address(0). When fee tier is unused place there any valid value. This
     *      value gets ignored.
     */
    function encodeSplitPath(
        uint256 _percentage,
        uint256 _fee1,
        address _token1,
        uint256 _fee2,
        address _token2,
        uint256 _fee3
    ) external pure returns (uint256) {
        return
            (_percentage << 12) +
            (encodeFeeTier(_fee1) << 10) +
            (encodeMiddleToken(_token1) << 7) +
            (encodeFeeTier(_fee2) << 5) +
            (encodeMiddleToken(_token2) << 2) +
            (encodeFeeTier(_fee3));
    }

    /**
     * @notice A function which encodes fee tier.
     * @param _feeTier - Fee tier in bps
     * @return Encoded fee tier (in the last 2 bits of uint)
     */
    function encodeFeeTier(uint256 _feeTier) public pure returns (uint256) {
        if (_feeTier == 100) {
            // Binary number 00
            return 0;
        }
        if (_feeTier == 500) {
            // Binary number 01
            return 1;
        }
        if (_feeTier == 3000) {
            // Binary number 10
            return 2;
        }
        if (_feeTier == 10000) {
            // Binary number 11
            return 3;
        }
        revert InvalidFeeTier();
    }

    /**
     * @notice A function which returns token encoding for a given token address.
     * @param _token - Token address
     * @return encodedToken - Encoded token (in the last 3 bits of uint64)
     */
    function encodeMiddleToken(address _token) public pure returns (uint256 encodedToken) {
        if (_token == address(0)) {
            // unused token
            return 0;
        }
        if (_token == WETH) {
            // binary number 001
            return 1;
        }
        if (_token == USDC) {
            // binary number 010
            return 2;
        }
        if (_token == USDT) {
            // binary number 011
            return 3;
        }
        if (_token == DAI) {
            // binary number 100
            return 4;
        }
        if (_token == WBTC) {
            // binary number 101
            return 5;
        }
        if (_token == FRAX) {
            // binary number 110
            return 6;
        }
        if (_token == BUSD) {
            // binary number 111
            return 7;
        }
        revert InvalidToken();
    }

    /**
     * @notice A function which deserializes encoded path to Path struct.
     * @param _tokenIn - Input ERC20 token
     * @param _encodedPath - Encoded path
     * @param _tokenOut - Output ERC20 token
     * @return path - Decoded/deserialized path struct
     */
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

    /**
     * @notice A function which returns a percentage of input going through the split path and the split path encoded
     *         in a format compatible with Uniswap router.
     * @param _tokenIn - Input ERC20 token
     * @param _encodedSplitPath - Encoded split path (in the last 19 bits of uint64)
     * @param _tokenOut - Output ERC20 token
     * @return percentage - A percentage of input going through the corresponding split path
     * @return splitPath - A split path encoded in a format compatible with Uniswap router
     */
    function _decodeSplitPath(
        address _tokenIn,
        uint64 _encodedSplitPath,
        address _tokenOut
    ) internal view returns (uint256 percentage, bytes memory splitPath) {
        uint64 fee3 = _encodedSplitPath & FEE_MASK;
        uint64 middleToken2 = (_encodedSplitPath >> 2) & TOKEN_MASK;
        uint64 fee2 = (_encodedSplitPath >> 5) & FEE_MASK;
        uint64 middleToken1 = (_encodedSplitPath >> 7) & TOKEN_MASK;
        uint64 fee1 = (_encodedSplitPath >> 10) & FEE_MASK;
        percentage = _encodedSplitPath >> 12;

        if (middleToken1 != 0 && middleToken2 != 0) {
            splitPath = abi.encodePacked(
                _tokenIn,
                _decodeFeeTier(fee1),
                _decodeMiddleToken(middleToken1),
                _decodeFeeTier(fee2),
                _decodeMiddleToken(middleToken2),
                _decodeFeeTier(fee3),
                _tokenOut
            );
        } else if (middleToken1 != 0) {
            splitPath = abi.encodePacked(
                _tokenIn,
                _decodeFeeTier(fee1),
                _decodeMiddleToken(middleToken1),
                _decodeFeeTier(fee3),
                _tokenOut
            );
        } else if (middleToken2 != 0) {
            splitPath = abi.encodePacked(
                _tokenIn,
                _decodeFeeTier(fee2),
                _decodeMiddleToken(middleToken2),
                _decodeFeeTier(fee3),
                _tokenOut
            );
        } else {
            splitPath = abi.encodePacked(_tokenIn, _decodeFeeTier(fee3), _tokenOut);
        }
    }

    /**
     * @notice A function which converts minimum price in a floating point format to integer.
     * @param _encodedMinPrice - Encoded minimum price (in the last 26 bits of uint64)
     * @return minPrice - Minimum acceptable price represented as an integer
     */
    function _decodeMinPrice(uint64 _encodedMinPrice) internal pure returns (uint256 minPrice) {
        // 21 bits significand, 5 bits exponent
        uint256 significand = _encodedMinPrice >> 5;
        uint256 exponent = _encodedMinPrice & EXPONENT_MASK;
        minPrice = significand * 10**exponent;
    }

    /**
     * @notice A function which converts encoded fee tier to a fee tier in an integer format.
     * @param _encodedFeeTier - Encoded fee tier (in the last 2 bits of uint64)
     * @return feeTier - Decoded fee tier in an integer format
     */
    function _decodeFeeTier(uint64 _encodedFeeTier) internal pure returns (uint24 feeTier) {
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

    /**
     * @notice A function which returns token address for an encoded token.
     * @param _encodedToken - Encoded token (in the last 3 bits of uint64)
     * @return token - Token address
     */
    function _decodeMiddleToken(uint256 _encodedToken) internal pure returns (address token) {
        if (_encodedToken == 1) {
            // binary number 001
            return WETH;
        }
        if (_encodedToken == 2) {
            // binary number 010
            return USDC;
        }
        if (_encodedToken == 3) {
            // binary number 011
            return USDT;
        }
        if (_encodedToken == 4) {
            // binary number 100
            return DAI;
        }
        if (_encodedToken == 5) {
            // binary number 101
            return WBTC;
        }
        if (_encodedToken == 6) {
            // binary number 110
            return FRAX;
        }
        if (_encodedToken == 7) {
            // binary number 111
            return BUSD;
        }
        revert InvalidTokenEncoding();
    }
}
