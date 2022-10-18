// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Test} from "forge-std/Test.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {IWETH} from "../../../interfaces/IWETH.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";

import {ISwapRouter} from "../../../interfaces/uniswapv3/ISwapRouter.sol";

import {UniswapDCABridge} from "../../../bridges/dca/UniswapDCABridge.sol";

contract BiDCATestE2E is BridgeTestBase {
    using SafeERC20 for IERC20;
    using SafeERC20 for ERC20;

    struct Sums {
        uint256 summedA;
        uint256 summedAInv;
        uint256 summedB;
        uint256 summedBInv;
    }

    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint160 private constant SQRT_PRICE_LIMIT_X96 = 1461446703485210103287273052203988822378723970341;

    IWETH internal constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address internal constant ORACLE = 0x773616E4d11A78F511299002da57A0a94577F1f4;

    address private constant ORIGIN = address(0xf00ba3);

    UniswapDCABridge internal bridge;
    IERC20 internal assetA;
    IERC20 internal assetB;

    AztecTypes.AztecAsset internal aztecAssetA;
    AztecTypes.AztecAsset internal aztecAssetB;
    uint256 internal bridgeAddressId;

    receive() external payable {}

    function receiveEthFromBridge(uint256 _interactionNonce) public payable {}

    function setUp() public {
        // Preparation
        assetA = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
        assetB = IERC20(address(WETH));

        bridge = new UniswapDCABridge(address(ROLLUP_PROCESSOR), 1 days, 10);

        vm.deal(address(bridge), 0);

        vm.startPrank(MULTI_SIG);

        ROLLUP_PROCESSOR.setSupportedAsset(address(WETH), 100000);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 200000);
        bridgeAddressId = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        vm.stopPrank();

        aztecAssetA = ROLLUP_ENCODER.getRealAztecAssetset(address(assetA));
        aztecAssetB = ROLLUP_ENCODER.getRealAztecAssetset(address(assetB));

        vm.label(address(assetA), "DAI");
        vm.label(address(assetB), "WETH");

        vm.deal(address(bridge), 0);
        vm.label(address(bridge), "Bridge");

        movePrice(0, 1e18);
    }

    function testUniswapForceFillAB() public {
        testFuzzUniswapForceFill(1000e18, 6, 1e18, 6, false, 1, 8);
    }

    function testUniswapForceFillBA() public {
        testFuzzUniswapForceFill(1e18, 6, 1000e18, 6, true, 1, 8);
    }

    /**
     * @notice Large fuzzing function that will fuzz
     * deposit of `_deposit1` asset (`_aFirst` ? A : B) for `_length1` time
     * increase time by `_timeDiff` days
     * deposit of `_deposit2` asset (`!_aFirst` ? A or B) for `_length2` time
     * increase time by `_ff` days
     * At this point, 0, 1 or both positions might be ready to finalise
     * Update the oracle price to increase A value
     * Rebalance fully + force fill rest on uniswap
     * There should be no available assets left, and the effective price should be an interpolation
     * meaning that a user going A -> B should have received more than a direct swap, and B -> A opposite
     */
    function testFuzzUniswapForceFill(
        uint256 _deposit1,
        uint8 _length1,
        uint256 _deposit2,
        uint8 _length2,
        bool _aFirst,
        uint8 _timediff,
        uint8 _ff
    ) public {
        uint256 deposit1 = bound(_deposit1, 0.1e18, !_aFirst ? 1000e18 : 1e24);
        uint256 deposit2 = bound(_deposit2, 0.1e18, _aFirst ? 1000e18 : 1e24);
        uint256 priceBefore = bridge.getPrice();

        {
            uint256 length1 = bound(_length1, 1, 14);
            uint256 length2 = bound(_length2, 1, 14);
            uint256 timediff = bound(_timediff, 1, 14);
            uint256 endTime = block.timestamp + (timediff + bound(_ff, 1, 15)) * 1 days;

            {
                // Poke the storage
                bridge.pokeNextTicks(length1 + length2 + timediff);
                uint256 nextTick = ((block.timestamp + 1 days - 1) / 1 days) + length1 + length2;
                bridge.pokeTicks(nextTick, timediff);
            }

            {
                // Deposit with asset A

                deal(address(_aFirst ? assetA : assetB), address(ROLLUP_PROCESSOR), deposit1);
                ROLLUP_ENCODER.defiInteractionL2(
                    bridgeAddressId,
                    _aFirst ? aztecAssetA : aztecAssetB,
                    emptyAsset,
                    _aFirst ? aztecAssetB : aztecAssetA,
                    emptyAsset,
                    uint64(length1),
                    deposit1
                );

                ROLLUP_ENCODER.processRollup();

                vm.warp(block.timestamp + timediff * 1 days);
            }
            {
                refreshTs();
                // Deposit2

                deal(address(_aFirst ? assetB : assetA), address(ROLLUP_PROCESSOR), deposit2);
                ROLLUP_ENCODER.defiInteractionL2(
                    bridgeAddressId,
                    _aFirst ? aztecAssetB : aztecAssetA,
                    emptyAsset,
                    _aFirst ? aztecAssetA : aztecAssetB,
                    emptyAsset,
                    uint64(length2),
                    deposit2
                );

                ROLLUP_ENCODER.processRollup();
                vm.warp(endTime);
            }
        }

        // Swap 1000 assetB for asset A. Will increase the value of asset A
        movePrice(0, 1000 ether);
        bridge.rebalanceAndFillUniswap();

        {
            // Finalise DCA position 0
            (uint256 acc, bool ready) = bridge.getAccumulated(0);
            uint256 outputValueA = (_aFirst ? assetB : assetA).balanceOf(address(ROLLUP_PROCESSOR));
            uint256 outputValueB = (_aFirst ? assetA : assetB).balanceOf(address(ROLLUP_PROCESSOR));
            bool interactionComplete;
            {
                uint256 originA = (_aFirst ? assetB : assetA).balanceOf(ORIGIN);
                uint256 originB = (_aFirst ? assetA : assetB).balanceOf(ORIGIN);

                vm.prank(address(this), ORIGIN);
                interactionComplete = ROLLUP_PROCESSOR.processAsyncDefiInteraction(0);
                outputValueA = (_aFirst ? assetB : assetA).balanceOf(address(ROLLUP_PROCESSOR)) - outputValueA;
                outputValueB = (_aFirst ? assetA : assetB).balanceOf(address(ROLLUP_PROCESSOR)) - outputValueB;

                uint256 incentiveA = ((_aFirst ? assetB : assetA).balanceOf(ORIGIN) - originA);
                uint256 incentiveB = ((_aFirst ? assetA : assetB).balanceOf(ORIGIN) - originB);

                if (interactionComplete) {
                    assertGt(incentiveA, 0, "No incentives received");
                }

                outputValueA += (_aFirst ? assetB : assetA).balanceOf(ORIGIN);
                outputValueB += (_aFirst ? assetA : assetB).balanceOf(ORIGIN);
            }

            if (bridge.getDCA(0).end <= (block.timestamp / bridge.TICK_SIZE())) {
                assertTrue(ready, "Not ready to finalise 0");
                assertEq(outputValueA, acc, "outputValueA not matching");
                assertEq(outputValueB, 0, "Outputvalue B not zero");
                assertTrue(interactionComplete, "Interaction failed");

                if (_aFirst) {
                    uint256 aToBDirect = bridge.denominateAssetAInB(deposit1, priceBefore, false);
                    assertGt(outputValueA, aToBDirect, "0 Received too little");
                } else {
                    uint256 bToADirect = bridge.denominateAssetBInA(deposit1, priceBefore, false);
                    assertLt(outputValueA, bToADirect, "0 Received too much A");
                }
            } else {
                assertFalse(ready, "Ready to finalise 0");
                assertEq(outputValueA, 0, "outputValueA not zero");
                assertEq(outputValueB, 0, "Outputvalue B not zero");
                assertFalse(interactionComplete, "Interaction passed");
            }
        }
        {
            // Finalise DCA position 1
            (uint256 acc, bool ready) = bridge.getAccumulated(32);

            uint256 outputValueA = (_aFirst ? assetA : assetB).balanceOf(address(ROLLUP_PROCESSOR));
            uint256 outputValueB = (_aFirst ? assetB : assetA).balanceOf(address(ROLLUP_PROCESSOR));
            bool interactionComplete;
            {
                uint256 originA = (_aFirst ? assetA : assetB).balanceOf(ORIGIN);
                uint256 originB = (_aFirst ? assetB : assetA).balanceOf(ORIGIN);

                vm.prank(address(this), ORIGIN);
                interactionComplete = ROLLUP_PROCESSOR.processAsyncDefiInteraction(32);
                outputValueA = (_aFirst ? assetA : assetB).balanceOf(address(ROLLUP_PROCESSOR)) - outputValueA;
                outputValueB = (_aFirst ? assetB : assetA).balanceOf(address(ROLLUP_PROCESSOR)) - outputValueB;

                uint256 incentiveA = ((_aFirst ? assetA : assetB).balanceOf(ORIGIN) - originA);
                uint256 incentiveB = ((_aFirst ? assetB : assetA).balanceOf(ORIGIN) - originB);
                if (interactionComplete) {
                    assertGt(incentiveA, 0, "No incentives received");
                }

                outputValueA += incentiveA;
                outputValueB += incentiveB;
            }

            if (bridge.getDCA(32).end <= (block.timestamp / bridge.TICK_SIZE())) {
                assertTrue(ready, "Not ready to finalise 1");
                assertEq(outputValueA, acc, "outputValueA not matching");
                assertEq(outputValueB, 0, "Outputvalue B not zero");
                assertTrue(interactionComplete, "Interaction failed");
                if (!_aFirst) {
                    uint256 aToBDirect = bridge.denominateAssetAInB(deposit2, priceBefore, false);
                    assertGt(outputValueA, aToBDirect, "1 Received too little");
                } else {
                    uint256 bToADirect = bridge.denominateAssetBInA(deposit2, priceBefore, false);
                    assertLt(outputValueA, bToADirect, "1 Received too much A");
                }
            } else {
                assertFalse(ready, "Ready to finalise 0");
                assertEq(outputValueA, 0, "outputValueA not zero");
                assertEq(outputValueB, 0, "Outputvalue B not zero");
                assertFalse(interactionComplete, "Interaction passed");
            }
        }

        {
            // Check that there are no available assets right now
            (uint256 availableA, uint256 availableB) = bridge.getAvailable();
            assertEq(availableA, 0, "Available A != 0");
            assertEq(availableB, 0, "Available B != 0");
        }

        {
            vm.warp(block.timestamp + 100 days);
            (uint256 availableA, uint256 availableB) = bridge.getAvailable();

            uint256 unaccountedA = assetA.balanceOf(address(bridge)) - availableA;
            uint256 unaccountedB = assetB.balanceOf(address(bridge)) - availableB;
            {
                if (bridge.getDCA(0).start != 0) {
                    (uint256 acc, ) = bridge.getAccumulated(0);
                    if (_aFirst) {
                        unaccountedB -= acc;
                    } else {
                        unaccountedA -= acc;
                    }
                }
                if (bridge.getDCA(32).start != 0) {
                    (uint256 acc, ) = bridge.getAccumulated(32);
                    if (_aFirst) {
                        unaccountedA -= acc;
                    } else {
                        unaccountedB -= acc;
                    }
                }
            }

            // We accumulate quite a large amount of dust from rounding errors etc with the amount of matching internally and crosstick. However, ensure it is less than 1 millionth
            assertLe(unaccountedA, (_aFirst ? deposit1 : deposit2) / 1e6, "too much A left as 'dust'");
            assertLe(unaccountedB, (_aFirst ? deposit2 : deposit1) / 1e6, "too much B left as 'dust'");
        }
    }

    function refreshTs() public {
        (, int256 answer, , , ) = bridge.ORACLE().latestRoundData();
        bytes memory returnValue = abi.encode(uint80(0), answer, uint256(0), block.timestamp, uint80(0));
        vm.mockCall(ORACLE, "", returnValue);
    }

    function setPrice(uint256 _newPrice) public {
        bytes memory returnValue = abi.encode(uint80(0), int256(_newPrice), uint256(0), block.timestamp, uint80(0));
        vm.mockCall(ORACLE, "", returnValue);

        emit log_named_decimal_uint("Setting Price", _newPrice, 18);

        assertEq(bridge.getPrice(), _newPrice, "Price not updated correctly");
    }

    function movePrice(uint256 _amountAToB, uint256 _amountBToA) public {
        ISwapRouter uniRouter = bridge.UNI_ROUTER();

        address user = address(0xdead);
        vm.startPrank(user);

        if (_amountAToB > 0) {
            deal(address(assetA), user, _amountAToB);
            assetA.approve(address(uniRouter), type(uint256).max);

            uint256 b = uniRouter.exactInput(
                ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(address(assetA), uint24(100), USDC, uint24(500), address(assetB)),
                    recipient: user,
                    deadline: block.timestamp,
                    amountIn: _amountAToB,
                    amountOutMinimum: 0
                })
            );

            uint256 price = (b * 1e18) / _amountAToB;
            setPrice(price);
        }

        if (_amountBToA > 0) {
            deal(address(assetB), user, _amountBToA);
            assetB.approve(address(uniRouter), type(uint256).max);

            uint256 a = uniRouter.exactInput(
                ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(address(assetB), uint24(500), USDC, uint24(100), address(assetA)),
                    recipient: user,
                    deadline: block.timestamp,
                    amountIn: _amountBToA,
                    amountOutMinimum: 0
                })
            );
            uint256 price = (_amountBToA * 1e18 + a - 1) / a;
            setPrice(price);
        }
        vm.stopPrank();
    }
}
