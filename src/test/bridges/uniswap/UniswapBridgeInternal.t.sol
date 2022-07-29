// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {UniswapBridge} from "../../../bridges/uniswap/UniswapBridge.sol";

contract UniswapBridgeInternalTest is Test, UniswapBridge(address(0)) {
    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address public constant LQTY = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;

    uint64 private maxEncodedMinPrice = 67108863; // ((2**21 - 1) << 5) + (2**5 - 1);
    uint256 private maxMinPrice = 20971519999999999999999999999999999999;
    uint256 private maxDecodedMinPriceAfterEncoding = 20971510000000000000000000000000000000;

    bytes private referenceSplitPath1 =
        abi.encodePacked(LUSD, uint24(500), USDC, uint24(3000), WETH, uint24(3000), LQTY);
    bytes private referenceSplitPath2 =
        abi.encodePacked(LUSD, uint24(500), DAI, uint24(3000), WETH, uint24(3000), LQTY);

    function setUp() public {}

    function testPreApproveTokensEmptyTokenArrays() public {
        address[] memory tokensIn = new address[](0);
        address[] memory tokensOut = new address[](0);
        this.preApproveTokens(tokensIn, tokensOut);
    }

    function testEncodePath() public {
        //            500     3000    3000
        // PATH1 LUSD -> USDC -> WETH -> LQTY   70% of input 1000110 01 010 10 001 10
        //            500    3000    3000
        // PATH2 LUSD -> DAI -> WETH -> LQTY    30% of input 0011110 01 100 10 001 10
        // MIN PRICE: significand 2000000, exponent 12
        // 111101000010010000000 01100 | 1000110 01 010 10 001 10 | 0011110 01 100 10 001 10
        uint64 referenceEncodedPath = 0xF42403232A31E646;
        uint64 encodedPath = this.encodePath(
            100e18,
            200e18,
            LUSD,
            SplitPath(70, 500, USDC, 3000, WETH, 3000),
            SplitPath(30, 500, DAI, 3000, WETH, 3000)
        );

        assertEq(encodedPath, referenceEncodedPath, "Encoded path is not equal to reference");
    }

    function testEncodeMinPriceForValuesWithoutPrecisionLoss(uint24 _price) public {
        uint256 price = bound(_price, 0, 2**21 - 1);
        uint256 encodedMinPrice = _computeEncodedMinPrice(1, price, 0);
        uint256 decodedMinPrice = _decodeMinPrice(encodedMinPrice);
        assertEq(decodedMinPrice, price);
    }

    function testMinPriceNever0DueToPrecisionLoss(uint24 _price, uint8 _decimals) public {
        uint256 decimals = bound(_decimals, 0, 24);
        uint256 price = bound(_price, 1, maxMinPrice / 10**decimals);
        uint256 encodedMinPrice = _computeEncodedMinPrice(1, price, decimals);
        uint256 decodedMinPrice = _decodeMinPrice(encodedMinPrice);
        assertGt(decodedMinPrice, 0);
    }

    function testPrecisionLossNeverBiggerThan1Bps(
        uint80 _totalInputValue,
        uint24 _price,
        uint8 _tokenInDecimals
    ) public {
        uint256 decimals = bound(_tokenInDecimals, 0, 24);
        uint256 price = bound(_price, 1, maxMinPrice / 10**decimals);
        uint256 quote = _totalInputValue * price;

        uint256 encodedMinPrice = _computeEncodedMinPrice(1, price, decimals);
        uint256 decodedMinPrice = _decodeMinPrice(encodedMinPrice);
        uint256 amountOutMinimum = (_totalInputValue * decodedMinPrice) / 10**decimals;

        assertApproxEqRel(quote, amountOutMinimum, 1e16);
    }

    function testEncodeMinPriceDoesntRevertAndDecodesToMax() public {
        uint256 encoded = _computeEncodedMinPrice(1, maxMinPrice, 0);
        assertEq(encoded, maxEncodedMinPrice, "Encoded price doesn't equal max encoded price");
        uint256 decoded = _decodeMinPrice(uint64(encoded));
        assertEq(
            decoded,
            maxDecodedMinPriceAfterEncoding,
            "Decoded max encoded doesn't equal max decoded after encoding"
        );
    }

    function testEncodeMinPriceRevertsForPriceBiggerThanBoundry() public {
        vm.expectRevert(UniswapBridge.Overflow.selector);
        _computeEncodedMinPrice(1, maxMinPrice + 1, 0);
    }

    function testDecodePath() public {
        //            500     3000    3000
        // PATH1 LUSD -> USDC -> WETH -> LQTY   70% of input 1000110 01 010 10 001 10
        //            500    3000    3000
        // PATH2 LUSD -> DAI -> WETH -> LQTY    30% of input 0011110 01 100 10 001 10
        // MIN PRICE: significand 2031142, exponent 27
        // 111101111111000100110 11011 | 0011110 01 100 10 001 10 | 1000110 01 010 10 001 10
        uint64 encodedPath = 0xF7F136CF32346546;
        UniswapBridge.Path memory path = _decodePath(LUSD, encodedPath, LQTY);

        assertEq(path.percentage1, 70, "Incorrect percentage 1");
        assertEq(string(path.splitPath1), string(referenceSplitPath1), "Split path 1 incorrectly encoded");
        assertEq(path.percentage2, 30, "Incorrect percentage 2");
        assertEq(string(path.splitPath2), string(referenceSplitPath2), "Split path 2 incorrectly encoded");
        assertEq(path.minPrice, 2031142 * 10**27);
    }

    function testDecodePathOnly1SplitPath() public {
        //            500     3000    3000
        // PATH1 LUSD -> USDC -> WETH -> LQTY   100% of input 1100100 01 010 10 001 10
        // MIN PRICE: significand 2031142, exponent 27
        // 111101111111000100110 11011 | 0000000 00 000 00 000 00 | 1100100 01 010 10 001 10
        uint64 encodedPath = 0xF7F136C000064546;
        UniswapBridge.Path memory path = _decodePath(LUSD, encodedPath, LQTY);

        assertEq(path.percentage1, 100, "Incorrect percentage 1");
        assertEq(string(path.splitPath1), string(referenceSplitPath1), "Split path 1 incorrectly encoded");
        assertEq(path.percentage2, 0, "Incorrect percentage 2");
        assertEq(path.minPrice, 2031142 * 10**27);
    }

    function testDecodePathOnly1SplitPathInPositionOfSplitPath2() public {
        //            500     3000    3000
        // PATH1 LUSD -> USDC -> WETH -> LQTY   100% of input 1100100 01 010 10 001 10
        // MIN PRICE: significand 2031142, exponent 27
        // 111101111111000100110 11011 | 1100100 01 100 10 001 10 | 0000000 00 000 00 000 00
        uint64 encodedPath = 0xF7F136F232300000;
        UniswapBridge.Path memory path = _decodePath(LUSD, encodedPath, LQTY);

        assertEq(path.percentage1, 0, "Incorrect percentage 1");
        assertEq(path.percentage2, 100, "Incorrect percentage 2");
        assertEq(string(path.splitPath2), string(referenceSplitPath2), "Split path 2 incorrectly encoded");
        assertEq(path.minPrice, 2031142 * 10**27);
    }

    function testDecodeSplitPathAllMiddleTokensUsed() public {
        // 100 %   500 USDC 3000 WETH 3000
        // 1100100 01  010  10   001  10
        uint64 encodedSplitPath = 0x64546;
        (uint256 percentage, bytes memory splitPath) = _decodeSplitPath(LUSD, encodedSplitPath, LQTY);
        assertEq(percentage, 100, "Incorrect percentage value");
        assertEq(string(splitPath), string(referenceSplitPath1), "Path incorrectly encoded");
    }

    function testDecodeSplitPathOneMiddleTokenUsed() public {
        bytes memory referenceSplitPath = abi.encodePacked(LUSD, uint24(500), USDC, uint24(3000), LQTY);

        // 70%     500 USDC 100  ---- 3000
        // 1000110 01  010  00   000  10
        uint64 encodedSplitPath = 0x46502;
        (uint256 percentage, bytes memory splitPath) = _decodeSplitPath(LUSD, encodedSplitPath, LQTY);
        assertEq(percentage, 70, "Incorrect percentage value");
        assertEq(string(splitPath), string(referenceSplitPath), "Path incorrectly encoded");
    }

    function testDecodeSplitPathNoMiddleTokenUsed() public {
        bytes memory referenceSplitPath = abi.encodePacked(LUSD, uint24(3000), LQTY);

        // 12%     100 ---  100  ---- 3000
        // 0001100 00  000  00   000  10
        uint64 encodedSplitPath = 0xC002;
        (uint256 percentage, bytes memory splitPath) = _decodeSplitPath(LUSD, encodedSplitPath, LQTY);
        assertEq(percentage, 12, "Incorrect percentage value");
        assertEq(string(splitPath), string(referenceSplitPath), "Path incorrectly encoded");
    }

    function testDecodeMinPrice() public {
        uint24 significand = 2031142;
        uint8 exponent = 27;
        // |111101111111000100110| [11011|
        uint64 referenceEncodedMinPrice = 0x3DFC4DB;
        uint256 referenceDecodedMinPrice = significand * 10**exponent;

        uint256 decodedMinPrice = _decodeMinPrice(referenceEncodedMinPrice);
        assertEq(decodedMinPrice, referenceDecodedMinPrice, "Incorrect min price");
    }

    function testDecodeMinPriceFuzz(uint24 _significand, uint8 _exponent) public {
        _significand = uint24(bound(_significand, 0, 2**21 - 1));
        _exponent = uint8(bound(_exponent, 0, 2**5 - 1));
        uint64 referenceEncodedMinPrice = (uint64(_significand) << 5) + _exponent;
        uint256 referenceDecodedMinPrice = _significand * 10**_exponent;

        uint256 decodedMinPrice = _decodeMinPrice(referenceEncodedMinPrice);
        assertEq(decodedMinPrice, referenceDecodedMinPrice, "Incorrect min price");
    }

    function testInvalidPercentageAmounts() public {
        // 00000000000000000000000000 | 0110010 01 100 10 001 10 | 1000110 01 010 10 001 10
        uint64 encodedPath = 0x1932346546;
        vm.expectRevert(UniswapBridge.InvalidPercentageAmounts.selector);
        _decodePath(LUSD, encodedPath, LQTY);
    }

    function testInvalidFeeTierEncoding() public {
        vm.expectRevert(UniswapBridge.InvalidFeeTierEncoding.selector);
        _decodeFeeTier(4);
    }

    function testInvalidTokenEncoding() public {
        vm.expectRevert(UniswapBridge.InvalidTokenEncoding.selector);
        _decodeMiddleToken(0);
    }
}
