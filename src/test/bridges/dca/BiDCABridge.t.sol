// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Test} from "forge-std/Test.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {ICERC20} from "../../../interfaces/compound/ICERC20.sol";
import {BiDCABridge} from "../../../bridges/dca/BiDCABridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

/**
 * @notice ERC20 token implementation that allow the owner to mint tokens and let anyone burn their own tokens
 * or token they have allowance to.
 * @dev The owner is immutable and therefore cannot be updated
 * @author Lasse Herskind
 */
contract Testtoken is ERC20 {
    error InvalidCaller();

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol) {}

    /**
     * @notice Mint tokens to address
     * @dev Only callable by the owner
     * @param _to The receiver of tokens
     * @param _amount The amount of tokens to mint
     */
    function mint(address _to, uint256 _amount) external {
        _mint(_to, _amount);
    }
}

contract BiDCATest_unit is Test {
    using SafeERC20 for IERC20;
    using SafeERC20 for ERC20;

    BiDCABridge internal bridge;
    IERC20 internal assetA;
    IERC20 internal assetB;

    AztecTypes.AztecAsset emptyAsset;
    AztecTypes.AztecAsset aztecAssetA;
    AztecTypes.AztecAsset aztecAssetB;

    function setUp() public {
        Testtoken a = new Testtoken("TokenA", "A", 18);
        Testtoken b = new Testtoken("TokenB", "B", 18);

        bridge = new BiDCABridge(address(this), address(a), address(b), 1 days);

        assetA = IERC20(address(a));
        assetB = IERC20(address(b));

        aztecAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(a),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        aztecAssetB = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(b),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
    }

    // Test a flow with 1 DCA position over 7 days, ff 2 days into the run, offer enough to match
    function testFlow1_7DCA_2days_MoreThanEnough() public {
        bridge.pokeNextTicks(10);

        uint256 startTick = block.timestamp / bridge.TICK_SIZE();

        // Deposit 700 A for selling over 7 days
        bridge.convert(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, 700 ether, 0, 7, address(0));
        deal(address(assetA), address(bridge), 1000 ether);

        {
            (uint256 a, uint256 b) = bridge.available();
            assertEq(a, 0);
            assertEq(b, 0);
        }

        vm.warp(block.timestamp + 2 days);
        {
            // Check the available amount of funds
            (uint256 a, uint256 b) = bridge.available();
            assertEq(a, 200e18, "Available A not matching");
            assertEq(b, 0, "Available B not matching");
        }
        {
            // Check the accumulated value of DCA(0)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, 0);
            assertFalse(ready);
        }

        {
            for (uint256 i = 1; i < 3; i++) {
                // Check tick[i]
                BiDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 100 ether, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
            }
        }

        deal(address(assetB), address(this), 1000 ether);
        assetB.approve(address(bridge), type(uint256).max);
        (int256 a, int256 b) = bridge.rebalanceAndfill(0, 10 ether);

        {
            // Check rabalance output values
            assertEq(a, -200 ether, "User did not buy 100 tokens");
            assertEq(assetA.balanceOf(address(this)), uint256(-a), "Asset A balance not matching");
            assertEq(b, 0.2 ether, "User did not sell 0.1 eth");
            assertEq(assetB.balanceOf(address(bridge)), uint256(b), "Asset B balance not matching");
        }

        {
            for (uint256 i = 1; i < 3; i++) {
                // Check tick[i]
                BiDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 0, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
                assertEq(tick.assetAToB.sold, 100 ether, "AToB sold not matching");
                assertEq(tick.assetAToB.bought, 0.1 ether, "AToB bought not matching");
                assertEq(tick.assetBToA.sold, 0, "BToA sold not matching");
                assertEq(tick.assetBToA.bought, 0, "AToB bought not matching");
            }
        }

        {
            // Check the accumulated value of DCA(0)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, 0.2 ether, "Accumulated not matching");
            assertFalse(ready, "Is ready");
        }
    }

    // Test a flow with 2 DCA position over 7 days, ff 2 days into the run, offer enough to match
    function testFlow2_7DCA_2days_MoreThanEnough() public {
        bridge.pokeNextTicks(10);
        uint256 startTick = block.timestamp / bridge.TICK_SIZE();

        // Deposit 700 A for selling over 7 days
        bridge.convert(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, 700 ether, 0, 7, address(0));
        vm.warp(block.timestamp + 1 days);
        bridge.convert(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, 1400 ether, 1, 7, address(0));
        deal(address(assetA), address(bridge), 2100 ether);

        {
            (uint256 a, uint256 b) = bridge.available();
            assertEq(a, 100 ether);
            assertEq(b, 0);
        }

        vm.warp(block.timestamp + 2 days);
        {
            // Check the available amount of funds
            (uint256 a, uint256 b) = bridge.available();
            assertEq(a, 300e18 + 400e18, "Available A not matching");
            assertEq(b, 0, "Available B not matching");
        }
        {
            // Check the accumulated value of DCA(0)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, 0);
            assertFalse(ready);
        }

        {
            {
                BiDCABridge.Tick memory tick = bridge.getTick(startTick + 1);
                assertEq(tick.availableA, 100e18, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0.001e18, "Price not matching");
            }
            for (uint256 i = 2; i < 8; i++) {
                // Check tick[i]
                BiDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 300e18, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
            }
            {
                BiDCABridge.Tick memory tick = bridge.getTick(startTick + 8);
                assertEq(tick.availableA, 200e18, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
            }
        }

        deal(address(assetB), address(this), 1000 ether);
        assetB.approve(address(bridge), type(uint256).max);
        (int256 a, int256 b) = bridge.rebalanceAndfill(0, 10 ether);

        {
            // Check rabalance output values
            assertEq(a, -(100e18 + 300e18 * 2), "User did not buy 700 tokens");
            assertEq(assetA.balanceOf(address(this)), uint256(-a), "Asset A balance not matching");
            assertEq(b, 0.7 ether, "User did not sell 0.6 eth");
            assertEq(assetB.balanceOf(address(bridge)), uint256(b), "Asset B balance not matching");
        }

        {
            {
                // Check tick[1]
                BiDCABridge.Tick memory tick = bridge.getTick(startTick + 1);
                assertEq(tick.availableA, 0, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0.001e18, "Price not matching");
                assertEq(tick.assetAToB.sold, 100 ether, "AToB sold not matching");
                assertEq(tick.assetAToB.bought, 0.1 ether, "AToB bought not matching");
                assertEq(tick.assetBToA.sold, 0, "BToA sold not matching");
                assertEq(tick.assetBToA.bought, 0, "AToB bought not matching");
            }
            for (uint256 i = 2; i < 4; i++) {
                // Check tick[i]
                BiDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 0, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
                assertEq(tick.assetAToB.sold, 300 ether, "AToB sold not matching");
                assertEq(tick.assetAToB.bought, 0.3 ether, "AToB bought not matching");
                assertEq(tick.assetBToA.sold, 0, "BToA sold not matching");
                assertEq(tick.assetBToA.bought, 0, "AToB bought not matching");
            }
        }

        {
            // Check the accumulated value of DCA(0)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, 0.3 ether, "Accumulated not matching");
            assertFalse(ready, "Is ready");
        }

        {
            // Check the accumulated value of DCA(1)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(1);
            assertEq(accumulated, 0.4 ether, "Accumulated not matching");
            assertFalse(ready, "Is ready");
        }
    }

    // Test a flow with 1 DCA position over 7 days, ff 8 days into the run, offer enough to match
    function testFlow1_7DCA_8days_MoreThanEnough() public {
        bridge.pokeNextTicks(10);
        uint256 startTick = block.timestamp / bridge.TICK_SIZE();
        // Deposit 700 A for selling over 7 days
        bridge.convert(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, 700 ether, 0, 7, address(0));
        deal(address(assetA), address(bridge), 1000 ether);

        {
            (uint256 a, uint256 b) = bridge.available();
            assertEq(a, 0);
            assertEq(b, 0);
        }

        vm.warp(block.timestamp + 8 days);
        {
            // Check the available amount of funds
            (uint256 a, uint256 b) = bridge.available();
            assertEq(a, 700e18, "Available A not matching");
            assertEq(b, 0, "Available B not matching");
        }
        {
            // Check the accumulated value of DCA(0)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, 0);
            assertFalse(ready);
        }

        {
            for (uint256 i = 1; i < 8; i++) {
                // Check tick[i]
                BiDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 100 ether, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
            }
        }

        deal(address(assetB), address(this), 1000 ether);
        assetB.approve(address(bridge), type(uint256).max);
        (int256 a, int256 b) = bridge.rebalanceAndfill(0, 10 ether);

        {
            // Check rabalance output values
            assertEq(a, -700 ether, "User did not buy 700 tokens");
            assertEq(assetA.balanceOf(address(this)), uint256(-a), "Asset A balance not matching");
            assertEq(b, 0.7 ether, "User did not sell 0.7 eth");
            assertEq(assetB.balanceOf(address(bridge)), uint256(b), "Asset B balance not matching");
        }

        {
            for (uint256 i = 1; i < 8; i++) {
                // Check tick[i]
                BiDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 0, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
                assertEq(tick.assetAToB.sold, 100 ether, "AToB sold not matching");
                assertEq(tick.assetAToB.bought, 0.1 ether, "AToB bought not matching");
                assertEq(tick.assetBToA.sold, 0, "BToA sold not matching");
                assertEq(tick.assetBToA.bought, 0, "AToB bought not matching");
            }
        }

        {
            // Check the accumulated value of DCA(0)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, 0.7 ether, "Accumulated not matching");
            assertTrue(ready, "Is ready");
        }
    }

    // Test a flow with 1 DCA position over 7 days, ff 2 days into the run, offer too little to match
    function testFlow1_7DCA_2days_OfferTooLittle() public {
        bridge.pokeNextTicks(10);
        uint256 startTick = block.timestamp / bridge.TICK_SIZE();
        // Deposit 700 A for selling over 7 days
        bridge.convert(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, 700 ether, 0, 7, address(0));
        deal(address(assetA), address(bridge), 1000 ether);

        {
            (uint256 a, uint256 b) = bridge.available();
            assertEq(a, 0);
            assertEq(b, 0);
        }

        vm.warp(block.timestamp + 2 days);
        {
            // Check the available amount of funds
            (uint256 a, uint256 b) = bridge.available();
            assertEq(a, 200e18, "Available A not matching");
            assertEq(b, 0, "Available B not matching");
        }
        {
            // Check the accumulated value of DCA(0)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, 0);
            assertFalse(ready);
        }

        {
            for (uint256 i = 1; i < 3; i++) {
                // Check tick[i]
                BiDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 100 ether, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
            }
        }

        deal(address(assetB), address(this), 1000 ether);
        assetB.approve(address(bridge), type(uint256).max);
        (int256 a, int256 b) = bridge.rebalanceAndfill(0, 0.1 ether);

        {
            // Check rabalance output values
            assertEq(a, -100 ether, "User did not buy 100 tokens");
            assertEq(assetA.balanceOf(address(this)), uint256(-a), "Asset A balance not matching");
            assertEq(b, 0.1 ether, "User did not sell 0.1 eth");
            assertEq(assetB.balanceOf(address(bridge)), uint256(b), "Asset B balance not matching");
        }

        {
            // Check tick 1
            BiDCABridge.Tick memory tick = bridge.getTick(startTick + 1);
            assertEq(tick.availableA, 0, "Available A not matching");
            assertEq(tick.availableB, 0, "Available B not matching");
            assertEq(tick.priceAToB, 0, "Price not matching");
            assertEq(tick.assetAToB.sold, 100 ether, "AToB sold not matching");
            assertEq(tick.assetAToB.bought, 0.1 ether, "AToB bought not matching");
            assertEq(tick.assetBToA.sold, 0, "BToA sold not matching");
            assertEq(tick.assetBToA.bought, 0, "AToB bought not matching");
        }

        {
            // Check tick 2
            BiDCABridge.Tick memory tick = bridge.getTick(startTick + 2);
            assertEq(tick.availableA, 100 ether, "Available A not matching");
            assertEq(tick.availableB, 0, "Available B not matching");
            assertEq(tick.priceAToB, 0, "Price not matching");
            assertEq(tick.assetAToB.sold, 0, "AToB sold not matching");
            assertEq(tick.assetAToB.bought, 0, "AToB bought not matching");
            assertEq(tick.assetBToA.sold, 0, "BToA sold not matching");
            assertEq(tick.assetBToA.bought, 0, "AToB bought not matching");
        }

        {
            // Check the accumulated value of DCA(0)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, 0.1 ether, "Accumulated not matching");
            assertFalse(ready, "Is ready");
        }
    }

    // Test a flow with 1 DCA position over 7 days, ff 8 days into the run, offer too little to match
    function testFlow1_7DCA_8days_OfferTooLittle() public {
        bridge.pokeNextTicks(10);
        uint256 startTick = block.timestamp / bridge.TICK_SIZE();
        // Deposit 700 A for selling over 7 days
        bridge.convert(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, 700 ether, 0, 7, address(0));
        deal(address(assetA), address(bridge), 1000 ether);

        {
            (uint256 a, uint256 b) = bridge.available();
            assertEq(a, 0);
            assertEq(b, 0);
        }

        vm.warp(block.timestamp + 8 days);
        {
            // Check the available amount of funds
            (uint256 a, uint256 b) = bridge.available();
            assertEq(a, 700e18, "Available A not matching");
            assertEq(b, 0, "Available B not matching");
        }
        {
            // Check the accumulated value of DCA(0)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, 0);
            assertFalse(ready);
        }

        {
            for (uint256 i = 1; i < 8; i++) {
                // Check tick[i]
                BiDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 100 ether, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
            }
        }

        deal(address(assetB), address(this), 1000 ether);
        assetB.approve(address(bridge), type(uint256).max);
        (int256 a, int256 b) = bridge.rebalanceAndfill(0, 0.15 ether);

        {
            // Check rabalance output values
            assertEq(a, -150 ether, "User did not buy 150 tokens");
            assertEq(assetA.balanceOf(address(this)), uint256(-a), "Asset A balance not matching");
            assertEq(b, 0.15 ether, "User did not sell 0.15 eth");
            assertEq(assetB.balanceOf(address(bridge)), uint256(b), "Asset B balance not matching");
        }

        {
            // Check tick 1
            BiDCABridge.Tick memory tick = bridge.getTick(startTick + 1);
            assertEq(tick.availableA, 0, "Available A not matching");
            assertEq(tick.availableB, 0, "Available B not matching");
            assertEq(tick.priceAToB, 0, "Price not matching");
            assertEq(tick.assetAToB.sold, 100 ether, "AToB sold not matching");
            assertEq(tick.assetAToB.bought, 0.1 ether, "AToB bought not matching");
            assertEq(tick.assetBToA.sold, 0, "BToA sold not matching");
            assertEq(tick.assetBToA.bought, 0, "AToB bought not matching");
        }

        {
            // Check tick 2
            BiDCABridge.Tick memory tick = bridge.getTick(startTick + 2);
            assertEq(tick.availableA, 50 ether, "Available A not matching");
            assertEq(tick.availableB, 0, "Available B not matching");
            assertEq(tick.priceAToB, 0, "Price not matching");
            assertEq(tick.assetAToB.sold, 50 ether, "AToB sold not matching");
            assertEq(tick.assetAToB.bought, 0.05 ether, "AToB bought not matching");
            assertEq(tick.assetBToA.sold, 0, "BToA sold not matching");
            assertEq(tick.assetBToA.bought, 0, "AToB bought not matching");
        }
        {
            for (uint256 i = 3; i < 8; i++) {
                // Check tick[i]
                BiDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 100 ether, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
                assertEq(tick.assetAToB.sold, 0, "AToB sold not matching");
                assertEq(tick.assetAToB.bought, 0, "AToB bought not matching");
                assertEq(tick.assetBToA.sold, 0, "BToA sold not matching");
                assertEq(tick.assetBToA.bought, 0, "AToB bought not matching");
            }
        }

        {
            // Check the accumulated value of DCA(0)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, 0.15 ether, "Accumulated not matching");
            assertFalse(ready, "Is ready");
        }
    }

    function testBiFlowPerfectMatch() public {
        bridge.pokeNextTicks(10);
        uint256 startTick = block.timestamp / bridge.TICK_SIZE();
        // Deposit 700 A for selling over 7 days
        bridge.convert(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, 700 ether, 0, 7, address(0));
        bridge.convert(aztecAssetB, emptyAsset, aztecAssetA, emptyAsset, 0.7 ether, 1, 7, address(0));
        deal(address(assetA), address(bridge), 700e18);
        deal(address(assetB), address(bridge), 0.7e18);

        {
            (uint256 a, uint256 b) = bridge.available();
            assertEq(a, 0);
            assertEq(b, 0);
        }

        vm.warp(block.timestamp + 8 days);
        {
            // Check the available amount of funds
            (uint256 a, uint256 b) = bridge.available();
            assertEq(a, 700e18, "Available A not matching");
            assertEq(b, 0.7e18, "Available B not matching");
        }
        {
            // Check the accumulated value of DCA(0)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, 0);
            assertFalse(ready);
        }
        {
            // Check the accumulated value of DCA(1)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(1);
            assertEq(accumulated, 0);
            assertFalse(ready);
        }

        {
            for (uint256 i = 1; i < 8; i++) {
                // Check tick[i]
                BiDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 100e18, "Available A not matching");
                assertEq(tick.availableB, 0.1e18, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
            }
        }

        (int256 a, int256 b) = bridge.rebalanceAndfill(0, 0);

        {
            // Check rabalance output values
            assertEq(a, 0 ether, "User did not buy 0 tokens");
            assertEq(b, 0 ether, "User did not sell 0 eth");
        }
        {
            for (uint256 i = 1; i < 8; i++) {
                // Check tick[i]
                BiDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 0, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
                assertEq(tick.assetAToB.sold, 100e18, "AToB sold not matching");
                assertEq(tick.assetAToB.bought, 0.1e18, "AToB bought not matching");
                assertEq(tick.assetBToA.sold, 0.1e18, "BToA sold not matching");
                assertEq(tick.assetBToA.bought, 100e18, "AToB bought not matching");
            }
        }

        {
            // Check the accumulated value of DCA(0)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, 0.7e18, "Accumulated not matching");
            assertTrue(ready, "Is not ready");
        }
        {
            // Check the accumulated value of DCA(1)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(1);
            assertEq(accumulated, 700e18, "Accumulated not matching");
            assertTrue(ready, "Is not ready");
        }

        {
            // Finalise DCA(0)
            (uint256 outputValueA, uint256 outputValueB, bool interactionComplete) = bridge.finalise(
                aztecAssetA,
                emptyAsset,
                aztecAssetB,
                emptyAsset,
                0,
                0
            );
            assertEq(outputValueA, 0.7e18, "OutputValue A not matching");
            assertEq(outputValueB, 0, "Outputvalue B not zero");
            assertTrue(interactionComplete, "Interaction failed");

            assetB.safeTransferFrom(address(bridge), address(this), outputValueA);
        }
        {
            // Finalise DCA(1)
            (uint256 outputValueA, uint256 outputValueB, bool interactionComplete) = bridge.finalise(
                aztecAssetB,
                emptyAsset,
                aztecAssetA,
                emptyAsset,
                1,
                0
            );
            assertEq(outputValueA, 700e18, "OutputValue A not matching");
            assertEq(outputValueB, 0, "Outputvalue B not zero");
            assertTrue(interactionComplete, "Interaction failed");

            assetA.safeTransferFrom(address(bridge), address(this), outputValueA);
        }
    }

    function testBiFlowMoreAThanB() public {
        bridge.pokeNextTicks(10);
        uint256 startTick = block.timestamp / bridge.TICK_SIZE();
        bridge.convert(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, 1400 ether, 0, 7, address(0));
        deal(address(assetA), address(bridge), 1400e18);

        vm.warp(block.timestamp + 1 days);

        bridge.convert(aztecAssetB, emptyAsset, aztecAssetA, emptyAsset, 0.7 ether, 1, 7, address(0));
        deal(address(assetB), address(bridge), 0.7e18);

        {
            (uint256 a, uint256 b) = bridge.available();
            assertEq(a, 200e18);
            assertEq(b, 0);
        }

        vm.warp(block.timestamp + 8 days);
        {
            // Check the available amount of funds
            (uint256 a, uint256 b) = bridge.available();
            assertEq(a, 1400e18, "Available A not matching");
            assertEq(b, 0.7e18, "Available B not matching");
        }
        {
            // Check the accumulated value of DCA(0)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, 0);
            assertFalse(ready);
        }
        {
            // Check the accumulated value of DCA(1)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(1);
            assertEq(accumulated, 0);
            assertFalse(ready);
        }

        {
            {
                // Check tick[1]
                BiDCABridge.Tick memory tick = bridge.getTick(startTick + 1);
                assertEq(tick.availableA, 200e18, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0.001e18, "Price not matching");
            }
            for (uint256 i = 2; i < 8; i++) {
                // Check tick[i]
                BiDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 200e18, "Available A not matching");
                assertEq(tick.availableB, 0.1e18, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
            }
            {
                // Check tick[8]
                BiDCABridge.Tick memory tick = bridge.getTick(startTick + 8);
                assertEq(tick.availableA, 0, "Available A not matching");
                assertEq(tick.availableB, 0.1e18, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
            }
        }

        // Some calls rebalance
        (int256 a, int256 b) = bridge.rebalanceAndfill(0, 0);

        {
            // Check rabalance output values
            assertEq(a, 0 ether, "User did not buy 0 tokens");
            assertEq(b, 0 ether, "User did not sell 0 eth");
        }
        {
            {
                // Check tick[1]
                BiDCABridge.Tick memory tick = bridge.getTick(startTick + 1);
                assertEq(tick.availableA, 200e18, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0.001e18, "Price not matching");
                assertEq(tick.assetAToB.sold, 0, "AToB sold not matching");
                assertEq(tick.assetAToB.bought, 0, "AToB bought not matching");
                assertEq(tick.assetBToA.sold, 0, "BToA sold not matching");
                assertEq(tick.assetBToA.bought, 0, "AToB bought not matching");
            }
            for (uint256 i = 2; i < 8; i++) {
                // Check tick[i]
                BiDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 100e18, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
                assertEq(tick.assetAToB.sold, 100e18, "AToB sold not matching");
                assertEq(tick.assetAToB.bought, 0.1e18, "AToB bought not matching");
                assertEq(tick.assetBToA.sold, 0.1e18, "BToA sold not matching");
                assertEq(tick.assetBToA.bought, 100e18, "AToB bought not matching");
            }
        }

        {
            // Check the accumulated value of DCA(0)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, 0.6e18, "Accumulated not matching");
            assertFalse(ready, "Is ready");
        }
        {
            // Check the accumulated value of DCA(1)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(1);
            assertEq(accumulated, 600e18, "Accumulated not matching");
            assertFalse(ready, "Is ready");
        }

        // Someone comes in an rebalance the alst by selling eth to the bridge;
        deal(address(assetB), address(this), 1 ether);
        assetB.approve(address(bridge), 1 ether);
        (int256 a2, int256 b2) = bridge.rebalanceAndfill(0, 1 ether);
        {
            // Check rabalance output values
            assertEq(a2, -800e18, "User did not buy 100 tokens");
            assertEq(b2, 0.8 ether, "User did not sell 0.1 eth");
        }

        {
            // Finalise DCA(0)
            (uint256 outputValueA, uint256 outputValueB, bool interactionComplete) = bridge.finalise(
                aztecAssetA,
                emptyAsset,
                aztecAssetB,
                emptyAsset,
                0,
                0
            );
            assertEq(outputValueA, 1.4e18, "OutputValue A not matching");
            assertEq(outputValueB, 0, "Outputvalue B not zero");
            assertTrue(interactionComplete, "Interaction failed");

            assetB.safeTransferFrom(address(bridge), address(this), outputValueA);
        }
        {
            // Finalise DCA(1)
            (uint256 outputValueA, uint256 outputValueB, bool interactionComplete) = bridge.finalise(
                aztecAssetB,
                emptyAsset,
                aztecAssetA,
                emptyAsset,
                1,
                0
            );
            assertEq(outputValueA, 0, "OutputValue A not matching");
            assertEq(outputValueB, 0, "Outputvalue B not zero");
            assertFalse(interactionComplete, "Interaction ready");

            assetA.safeTransferFrom(address(bridge), address(this), outputValueA);
        }
    }

    function printDCA(uint256 _nonce) public returns (BiDCABridge.DCA memory) {
        (uint256 accumulated, bool ready) = bridge.getAccumulated(_nonce);
        BiDCABridge.DCA memory dca = bridge.getDCA(_nonce);
        emit log_named_uint("DCA at nonce", _nonce);
        emit log_named_decimal_uint("Total ", dca.total, 18);
        emit log_named_uint("start ", dca.start);
        emit log_named_uint("end   ", dca.end);
        if (dca.assetA) {
            emit log_named_decimal_uint("accumB", accumulated, 18);
        } else {
            emit log_named_decimal_uint("accumA", accumulated, 18);
        }
        if (ready) {
            emit log("Ready for harvest");
        }
    }

    function printAvailable() public {
        (uint256 a, uint256 b) = bridge.available();
        emit log_named_decimal_uint("Available A", a, 18);
        emit log_named_decimal_uint("Available B", b, 18);
    }

    function printTick(uint256 _tick) public returns (BiDCABridge.Tick memory) {
        BiDCABridge.Tick memory tick = bridge.getTick(_tick);

        emit log_named_uint("Tick number", _tick);
        emit log_named_decimal_uint("availableA", tick.availableA, 18);
        emit log_named_decimal_uint("availableB", tick.availableB, 18);
        emit log_named_decimal_uint("price aToB", tick.priceAToB, 18);

        emit log_named_decimal_uint("A sold    ", tick.assetAToB.sold, 18);
        emit log_named_decimal_uint("A bought  ", tick.assetAToB.bought, 18);

        emit log_named_decimal_uint("B sold    ", tick.assetBToA.sold, 18);
        emit log_named_decimal_uint("B bought  ", tick.assetBToA.bought, 18);

        return tick;
    }
}
