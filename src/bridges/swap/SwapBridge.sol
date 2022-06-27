// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
pragma solidity >=0.8.4;

import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {ISwapRouter} from "../../interfaces/uniswapv3/ISwapRouter.sol";

contract SwapBridge is BridgeBase {
    error InvalidFeeTierEncoding();
    error InvalidTokenEncoding();
    error InvalidPercentageAmounts();
    error InsufficientAmountOut();

    // TODO: consider packing
    struct Path {
        uint256 percentage1;
        bytes splitPath1;
        uint256 percentage2;
        bytes splitPath2;
        uint256 minPrice;
    }

    ISwapRouter public constant UNI_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    uint64 private constant SPLIT_PATH_BIT_LENGTH = 19;
    uint64 private constant SPLIT_PATHS_BIT_LENGTH = 38; // SPLIT_PATH_BIT_LENGTH * 2
    uint64 private constant PRICE_BIT_LENGTH = 26; // 64 - SPLIT_PATHS_BIT_LENGTH

    /**
     * @dev The following masks are used to decode 2 split paths and minimum acceptable price from 1 uint64.
     *      1 split path is encoded as follows:
     *      |7 bits percentage| |2 bits fee| |3 bits middle token| |2 bits fee| |3 bits middle token| |2 bits fee|
     *      The meaning of percentage is how much of input amount will be routed through this split path.
     *      Fee bits are mapped to specific fee tiers as follows: 00 is 0.01%, 01 is 0.05%, 10 is 0.3%, 11 is 1%
     *      Middle tokens use this mapping:
     *      001 is ETH, 010 is USDC, 011 is USDT, 100 is DAI, 101 is WBTC, 110 is FRAX, 111 is BUSD,
     *      000 means the middle token is unused
     */

    // Binary number 0000000000000000000000000000000000000000000001111111111111111111 (last 19 bits)
    uint64 private constant SPLIT_PATH_MASK = 0x7FFFF;

    // Binary number 0000000000000000000000000000000000000011111111111111111111111111 (last 26 bits)
    uint64 private constant PRICE_MASK = 0x3FFFFFF;

    // Binary number 11
    uint64 private constant FEE_MASK = 0x3;
    // Binary number 111
    uint64 private constant TOKEN_MASK = 0x7;

    /**
     * @notice Set the address of rollup processor.
     * @param _rollupProcessor Address of rollup processor
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _inputValue,
        uint256,
        uint64 _auxData,
        address
    )
        external
        payable
        override(BridgeBase)
        returns (
            uint256 outputValueA,
            uint256,
            bool
        )
    {
        if (_inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert ErrorLib.InvalidInputA();
        if (_outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert ErrorLib.InvalidOutputA();

        Path memory path = _decodePath(_inputAssetA.erc20Address, _auxData, _outputAssetA.erc20Address);

        uint256 amountOut = UNI_ROUTER.exactInput(
            ISwapRouter.ExactInputParams({
                path: path.splitPath1,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _inputValue,
                amountOutMinimum: 0
            })
        );

        if (path.percentage2 != 0) {
            amountOut += UNI_ROUTER.exactInput(
                ISwapRouter.ExactInputParams({
                    path: path.splitPath2,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: _inputValue,
                    amountOutMinimum: 0
                })
            );
        }

        if (amountOut < path.minPrice * _inputValue) revert InsufficientAmountOut();
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
        } else {
            path = abi.encodePacked(_tokenIn, _getFeeTier(fee3), _tokenOut);
        }
    }

    function _decodeMinPrice(uint64 _encodedSlippage) internal pure returns (uint256 minPrice) {
        // TODO
        return _encodedSlippage;
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
