// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ExampleBridgeContract} from "../../../bridges/example/ExampleBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {SwapBridge} from "../../../bridges/swap/SwapBridge.sol";

contract SwapBridgeTest is BridgeTestBase {
    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant LQTY = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    // The reference to the example bridge
    SwapBridge internal bridge;

    // To store the id of the swap bridge after being added
    uint256 private id;

    function setUp() public {
        // Deploy a new example bridge
        bridge = new SwapBridge(address(ROLLUP_PROCESSOR));

        // use the label cheatcode to mark the address with "Example Bridge" in the traces
        vm.label(address(bridge), "Swap Bridge");
        vm.label(address(bridge.UNI_ROUTER()), "Uni Router");
        vm.label(LUSD, "LUSD");
        vm.label(DAI, "DAI");
        vm.label(WETH, "WETH");
        vm.label(LQTY, "LQTY");
        vm.label(USDC, "USDC");

        // Impersonate the multi-sig to add a new bridge
        vm.prank(MULTI_SIG);

        // List the example-bridge with a gasLimit of 100K
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 100000);

        // Fetch the id of the example bridge
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();
    }

    function testInvalidInputAssetAType() public {
        vm.prank(address(ROLLUP_PROCESSOR));
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

        vm.startPrank(address(ROLLUP_PROCESSOR));
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

        IERC20(outputAssetA.erc20Address).transferFrom(address(bridge), address(ROLLUP_PROCESSOR), outputValueA);

        vm.stopPrank();

        assertGt(outputValueA, 0);
    }

    function testSwapEth() public {
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

        deal(address(ROLLUP_PROCESSOR), swapAmount);

        vm.startPrank(address(ROLLUP_PROCESSOR));
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

        IERC20(outputAssetA.erc20Address).transferFrom(address(bridge), address(ROLLUP_PROCESSOR), outputValueA);

        vm.stopPrank();

        assertGt(outputValueA, 0);
    }
}
