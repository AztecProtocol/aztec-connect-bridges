// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {UniswapBridge} from "../../../bridges/uniswap/UniswapBridge.sol";
import {IQuoter} from "../../../interfaces/uniswapv3/IQuoter.sol";

contract UniswapBridgeE2ETest is BridgeTestBase {
    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant LQTY = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    IQuoter public constant QUOTER = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);

    bytes private referenceSplitPath1 =
        abi.encodePacked(LUSD, uint24(500), USDC, uint24(3000), WETH, uint24(3000), LQTY);
    bytes private referenceSplitPath2 =
        abi.encodePacked(LUSD, uint24(500), DAI, uint24(3000), WETH, uint24(10000), LQTY);

    UniswapBridge private bridge;

    // To store the id of the swap bridge after being added
    uint256 private id;

    function setUp() public {
        // Deploy the bridge
        bridge = new UniswapBridge(address(ROLLUP_PROCESSOR));

        // Use the label cheatcode to mark addresses in the traces
        vm.label(address(bridge), "Swap Bridge");
        vm.label(address(bridge.ROUTER()), "Uni Router");
        vm.label(LUSD, "LUSD");
        vm.label(DAI, "DAI");
        vm.label(WETH, "WETH");
        vm.label(LQTY, "LQTY");
        vm.label(USDC, "USDC");

        // Impersonate the multi-sig to add a new bridge and assets
        vm.startPrank(MULTI_SIG);

        // List the example-bridge with a gasLimit of 1M
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 1000000);

        // List the assets with a gasLimit of 100k
        ROLLUP_PROCESSOR.setSupportedAsset(LUSD, 100000);
        ROLLUP_PROCESSOR.setSupportedAsset(LQTY, 100000);

        vm.stopPrank();

        // Fetch the id of the example bridge
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        // EIP-1087 optimization related mints
        deal(LQTY, address(bridge), 1);
        deal(LUSD, address(bridge), 1);
        deal(WETH, address(bridge), 1);
    }

    function testSwap() public {
        uint256 swapAmount = 1e21; // 1000 LUSD

        //            500     3000    3000
        // PATH1 LUSD -> USDC -> WETH -> LQTY   70% of input 1000110 01 010 10 001 10
        //            500    3000    10000
        // PATH2 LUSD -> DAI -> WETH -> LQTY    30% of input 0011110 01 100 10 001 11
        // MIN PRICE: significand 0, exponent 0
        // @dev Setting min price to 0 here in order to avoid issues with changing mainnet liquidity
        // 000000000000000000000 00000 | 0011110 01 100 10 001 11 | 1000110 01 010 10 001 10
        uint64 encodedPath = 0xF323C6546;

        address[] memory tokensIn = new address[](1);
        tokensIn[0] = LUSD;

        address[] memory tokensOut = new address[](1);
        tokensOut[0] = LQTY;

        bridge.preApproveTokens(tokensIn, tokensOut);

        // Define input and output assets
        AztecTypes.AztecAsset memory lusdAsset = getRealAztecAsset(LUSD);
        AztecTypes.AztecAsset memory lqtyAsset = getRealAztecAsset(LQTY);

        deal(LUSD, address(ROLLUP_PROCESSOR), swapAmount);

        // Compute quote
        uint256 swapAmountSplitPath1 = (swapAmount * 70) / 100;
        uint256 quote = QUOTER.quoteExactInput(referenceSplitPath1, swapAmountSplitPath1);
        quote += QUOTER.quoteExactInput(referenceSplitPath2, swapAmount - swapAmountSplitPath1);

        // Computes the encoded data for the specific bridge interaction
        uint256 bridgeCallData = encodeBridgeCallData(id, lusdAsset, emptyAsset, lqtyAsset, emptyAsset, encodedPath);

        vm.expectEmit(true, true, false, true);
        // Second part of cheatcode, emit the event that we are to match against.
        emit DefiBridgeProcessed(bridgeCallData, getNextNonce(), swapAmount, quote, 0, true, "");

        // Execute the rollup with the bridge interaction. Ensure that event as seen above is emitted.
        sendDefiRollup(bridgeCallData, swapAmount);
    }
}
