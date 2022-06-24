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
        uint256 amountOutMinimum;
    }

    ISwapRouter public constant UNI_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    // @dev The following masks are used to decode multiple paths from 1 uint64. There can be 3 paths encoded in
    //      auxData. (19 bits per path, 7 bits per slippage --> 3 * 19 + 7 = 64)
    //      1 path consists of |2 bits fee| |3 bits middle token| |2 bits fee| |3 bits middle token| |2 bits fee|
    //      Fee bits are mapped to specific fee tiers as follows: 00 is 0.01%, 01 is 0.05%, 10 is 0.3%, 11 is 1%
    //      Slippage is also mapped to predefined values: TODO
    uint64 private constant PATH_BIT_LENGTH = 19;
    uint64 private constant PATHS_BIT_LENGTH = 38;
    // Binary number 0000000000000000000000000000000000000000000001111111111111111111 (last 19 bits)
    uint64 private constant PATH_MASK = 0x7FFFF;

    uint64 private constant PRICE_BIT_LENGTH = 26;
    // Binary number 0000000000000000000000000000000000000011111111111111111111111111 (last 26 bits)
    uint64 private constant PRICE_MASK = 0x3FFFFFF;

    // Binary number 11
    uint64 private constant FEE_MASK = 0x3;
    // Binary number 111
    uint64 private constant TOKEN_MASK = 0x7;

    /**
     * @notice Set the address of RollupProcessor.sol.
     * @param _rollupProcessor Address of the RollupProcessor.sol
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

        if (amountOut < path.amountOutMinimum) revert InsufficientAmountOut();
    }

    function _decodePath(
        address _tokenIn,
        uint64 _encodedPath,
        address _tokenOut
    ) internal view returns (Path memory path) {
        (uint256 percentage1, bytes memory splitPath1) = _decodeSplitPath(
            _tokenIn,
            _encodedPath & PATH_MASK,
            _tokenOut
        );
        path.percentage1 = percentage1;
        path.splitPath1 = splitPath1;

        (uint256 percentage2, bytes memory splitPath2) = _decodeSplitPath(
            _tokenIn,
            (_encodedPath >> PATH_BIT_LENGTH) & PATH_MASK,
            _tokenOut
        );

        if (percentage1 + percentage2 != 100) revert InvalidPercentageAmounts();

        path.percentage2 = percentage2;
        path.splitPath2 = splitPath2;
        path.amountOutMinimum = _decodeAmountOutMinimum(_encodedPath >> PATHS_BIT_LENGTH);
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

    function _decodeAmountOutMinimum(uint64 _encodedSlippage) internal pure returns (uint256 amountOutMinimum) {
        // TODO
        return _encodedSlippage;
    }

    function _getFeeTier(uint64 _encodedFeeTier) private pure returns (uint24 feeTier) {
        if (_encodedFeeTier == 0) {
            return uint24(100);
        }
        if (_encodedFeeTier == 1) {
            return uint24(500);
        }
        if (_encodedFeeTier == 2) {
            return uint24(3000);
        }
        if (_encodedFeeTier == 3) {
            return uint24(10000);
        }
        revert InvalidFeeTierEncoding();
    }

    function _getMiddleToken(uint256 _encodedToken) private pure returns (address token) {
        if (_encodedToken == 1) {
            // ETH
            return 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        }
        if (_encodedToken == 2) {
            // USDC
            return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        }
        if (_encodedToken == 3) {
            // USDT
            return 0xdAC17F958D2ee523a2206206994597C13D831ec7;
        }
        if (_encodedToken == 4) {
            // DAI
            return 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        }
        if (_encodedToken == 5) {
            // WBTC
            return 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
        }
        if (_encodedToken == 6) {
            // FRAX
            return 0x853d955aCEf822Db058eb8505911ED77F175b99e;
        }
        if (_encodedToken == 7) {
            // BUSD
            return 0x4Fabb145d64652a948d72533023f6E7A623C7C53;
        }
        revert InvalidTokenEncoding();
    }
}
