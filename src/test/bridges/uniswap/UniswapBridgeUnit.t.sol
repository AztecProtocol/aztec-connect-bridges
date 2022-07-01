// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {UniswapBridge} from "../../../bridges/uniswap/UniswapBridge.sol";
import {IQuoter} from "../../../interfaces/uniswapv3/IQuoter.sol";

contract UniswapBridgeUnitTest is Test {
    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant LQTY = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant GUSD = 0x056Fd409E1d7A124BD7017459dFEa2F387b6d5Cd; // Gemini USD, only 2 decimals

    IQuoter public constant QUOTER = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);

    AztecTypes.AztecAsset internal emptyAsset;

    address private rollupProcessor;
    UniswapBridge private bridge;

    function receiveEthFromBridge(uint256 _interactionNonce) external payable {}

    function setUp() public {
        rollupProcessor = address(this);

        // Deploy the bridge
        bridge = new UniswapBridge(rollupProcessor);
        // Set ETH balance to 0 for clarity
        vm.deal(address(bridge), 0);

        // Use the label cheatcode to mark addresses in the traces
        vm.label(address(bridge), "Swap Bridge");
        vm.label(address(bridge.UNI_ROUTER()), "Uni Router");
        vm.label(LUSD, "LUSD");
        vm.label(DAI, "DAI");
        vm.label(WETH, "WETH");
        vm.label(LQTY, "LQTY");
        vm.label(USDC, "USDC");
        vm.label(GUSD, "GUSD");

        // EIP-1087 optimization related mints
        deal(LQTY, address(bridge), 1);
        deal(LUSD, address(bridge), 1);
        deal(WETH, address(bridge), 1);
    }

    function testInvalidInputAssetAType() public {
        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function testSwap() public {
        uint256 swapAmount = 1e21; // 1000 LUSD

        //            500     3000    3000
        // PATH1 LUSD -> USDC -> WETH -> LQTY   70% of input 1000110 01 010 10 001 10
        //            500    3000    3000
        // PATH2 LUSD -> DAI -> WETH -> LQTY    30% of input 0011110 01 100 10 001 10
        // MIN PRICE: significand 0, exponent 0
        // @dev Setting min price to 0 here in order to avoid issues with changing mainnet liquidity
        // 000000000000000000000 00000 | 0011110 01 100 10 001 10 | 1000110 01 010 10 001 10
        uint64 encodedPath = 0xF32346546;

        bridge.preApproveTokenPair(LUSD, LQTY);

        // Define input and output assets
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: LUSD,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: LQTY,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        deal(LUSD, address(bridge), swapAmount);

        (uint256 outputValueA, , ) = bridge.convert(
            inputAssetA,
            emptyAsset,
            outputAssetA,
            emptyAsset,
            swapAmount,
            0,
            encodedPath,
            address(0)
        );

        IERC20(outputAssetA.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueA);

        assertGt(outputValueA, 0);
    }

    function testSwapEthIn() public {
        uint256 swapAmount = 10 ether;

        //           3000
        // PATH1 ETH  -> LQTY   85% of input 1010101 00 000 00 000 10
        //           10000
        // PATH2 ETH  -> LQTY   15% of input 0001111 00 000 00 000 11
        // MIN PRICE: significand 0, exponent 0
        // 000000000000000000000 00000 | 1010101 00 000 00 000 10 | 0001111 00 000 00 000 11
        uint64 encodedPath = 0x2A8010F003;

        bridge.preApproveTokenPair(address(0), LQTY);

        // Define input and output assets
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 0,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.ETH
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: LQTY,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        deal(rollupProcessor, swapAmount);

        (uint256 outputValueA, , ) = bridge.convert{value: swapAmount}(
            inputAssetA,
            emptyAsset,
            outputAssetA,
            emptyAsset,
            swapAmount,
            0,
            encodedPath,
            address(0)
        );

        IERC20(outputAssetA.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueA);

        assertGt(outputValueA, 0);
    }

    function testSwapEthOut() public {
        uint256 swapAmount = 1e22; // 10k LQTY

        //           3000
        // PATH1 LQTY  -> ETH   85% of input 1010101 00 000 00 000 10
        //           10000
        // PATH2 LQTY  -> ETH   15% of input 0001111 00 000 00 000 11
        // MIN PRICE: significand 0, exponent 0
        // 000000000000000000000 00000 | 1010101 00 000 00 000 10 | 0001111 00 000 00 000 11
        uint64 encodedPath = 0x2A8010F003;

        bridge.preApproveTokenPair(LQTY, address(0));

        // Define input and output assets
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: LQTY,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 0,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.ETH
        });

        deal(LQTY, address(bridge), swapAmount);

        (uint256 outputValueA, , ) = bridge.convert(
            inputAssetA,
            emptyAsset,
            outputAssetA,
            emptyAsset,
            swapAmount,
            0,
            encodedPath,
            address(0)
        );

        assertGt(outputValueA, 0);
    }

    function testSwapHighToLowDecimals(uint80 _swapAmount) public {
        // Trying to swap anywhere from 0.1 ETH to 10 thousand ETH
        uint256 swapAmount = bound(_swapAmount, 1e17, 1e22);

        uint256 quote = QUOTER.quoteExactInput(
            abi.encodePacked(WETH, uint24(500), USDC, uint24(3000), GUSD),
            swapAmount
        );

        uint256 desiredMinPrice = quote / swapAmount;

        uint64 encodedPath = uint64(
            (bridge.encodeMinPrice(desiredMinPrice) << bridge.SPLIT_PATHS_BIT_LENGTH()) +
                (bridge.encodeSplitPath(100, 500, USDC, 100, address(0), 3000))
        );

        bridge.preApproveTokenPair(WETH, GUSD);

        // Define input and output assets
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: WETH,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 4,
            erc20Address: GUSD,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        deal(WETH, address(bridge), swapAmount);

        (uint256 outputValueA, , ) = bridge.convert(
            inputAssetA,
            emptyAsset,
            outputAssetA,
            emptyAsset,
            swapAmount,
            0,
            encodedPath,
            address(0)
        );

        IERC20(outputAssetA.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueA);

        assertGt(outputValueA, 0);
    }

    function testSwapLowToHighDecimals(uint48 _swapAmount) public {
        // Trying to swap anywhere from 1 USDC to 10 million USDC
        uint256 swapAmount = bound(_swapAmount, 1e6, 1e13);

        uint256 quote = QUOTER.quoteExactInput(abi.encodePacked(USDC, uint24(500), WETH), swapAmount);
        uint256 desiredMinPrice = quote / swapAmount;

        uint64 encodedPath = uint64(
            (bridge.encodeMinPrice(desiredMinPrice) << bridge.SPLIT_PATHS_BIT_LENGTH()) +
                (bridge.encodeSplitPath(100, 100, address(0), 100, address(0), 500))
        );

        bridge.preApproveTokenPair(USDC, WETH);

        // Define input and output assets
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 4,
            erc20Address: USDC,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: WETH,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        deal(USDC, address(bridge), swapAmount);

        (uint256 outputValueA, , ) = bridge.convert(
            inputAssetA,
            emptyAsset,
            outputAssetA,
            emptyAsset,
            swapAmount,
            0,
            encodedPath,
            address(0)
        );

        IERC20(outputAssetA.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueA);

        assertGt(outputValueA, 0);
    }

    function testInsufficientAmountOut() public {
        // Testing that InsufficientAmountOut error is thrown by passing in a 1 million Dai as a minimum acceptable
        // amount for 1 ETH.
        uint256 swapAmount = 1 ether;

        //           500     100
        // PATH1 ETH -> USDC -> DAI   100% of input 1100100 01 010 00 000 00
        // MIN PRICE: significand 1, exponent 24
        // 000000000000000000001 10111 | 0000000 00 000 00 000 00 | 1100100 01 010 00 000 00
        uint64 encodedPath = 0xDC000064500;

        bridge.preApproveTokenPair(address(0), DAI);

        // Define input and output assets
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 0,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.ETH
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: DAI,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        deal(rollupProcessor, swapAmount);

        vm.expectRevert(UniswapBridge.InsufficientAmountOut.selector);
        bridge.convert{value: swapAmount}(
            inputAssetA,
            emptyAsset,
            outputAssetA,
            emptyAsset,
            swapAmount,
            0,
            encodedPath,
            address(0)
        );
    }
}
