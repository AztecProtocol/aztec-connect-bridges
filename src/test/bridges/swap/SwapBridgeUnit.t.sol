// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {SwapBridge} from "../../../bridges/swap/SwapBridge.sol";

contract SwapBridgeUnitTest is Test {
    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant LQTY = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    AztecTypes.AztecAsset internal emptyAsset;

    address private rollupProcessor;
    SwapBridge private bridge;

    function receiveEthFromBridge(uint256 _interactionNonce) external payable {}

    function setUp() public {
        rollupProcessor = address(this);

        // Deploy the bridge
        bridge = new SwapBridge(rollupProcessor);

        // Use the label cheatcode to mark addresses in the traces
        vm.label(address(bridge), "Swap Bridge");
        vm.label(address(bridge.UNI_ROUTER()), "Uni Router");
        vm.label(LUSD, "LUSD");
        vm.label(DAI, "DAI");
        vm.label(WETH, "WETH");
        vm.label(LQTY, "LQTY");
        vm.label(USDC, "USDC");
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
}
