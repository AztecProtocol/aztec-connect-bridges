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
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {IWETH} from "../../../interfaces/IWETH.sol";

import {ISwapRouter} from "../../../interfaces/uniswapv3/ISwapRouter.sol";

import {TestDCABridge} from "./TestDCABridge.sol";

/**
 * @notice ERC20 token implementation useful in testing
 * @author Lasse Herskind
 */
contract Testtoken is ERC20 {
    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals
    ) ERC20(_name, _symbol) {}

    /**
     * @notice Mint tokens to address
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

    TestDCABridge internal bridge;
    IERC20 internal assetA;
    IERC20 internal assetB;

    AztecTypes.AztecAsset emptyAsset;
    AztecTypes.AztecAsset aztecAssetA;
    AztecTypes.AztecAsset aztecAssetB;

    receive() external payable {}

    function receiveEthFromBridge(uint256 _interactionNonce) public payable {}

    function setUp() public {
        // Preparation
        assetA = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
        assetB = IERC20(address(WETH));
        bridge = new TestDCABridge(address(this), address(assetA), address(assetB), 1 days, ORACLE);
        aztecAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(assetA),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        aztecAssetB = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(assetB),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        vm.label(address(assetA), "DAI");
        vm.label(address(assetB), "WETH");

        vm.deal(address(bridge), 0);
        vm.label(address(bridge), "Bridge");
    }

    function testRounding(uint128 _a, uint96 _price) public {
        vm.assume(_a > 0 && _price > 0);
        uint256 b = bridge.assetAInAssetB(_a, _price, false);
        uint256 a = bridge.assetBInAssetA(b, _price, true);

        assertGe(_a, a);
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
            }

            {
                movePrice(1e18, 0);
                // Deposit with asset A
                bridge.convert(
                    _aFirst ? aztecAssetA : aztecAssetB,
                    emptyAsset,
                    _aFirst ? aztecAssetB : aztecAssetA,
                    emptyAsset,
                    deposit1,
                    0,
                    uint64(length1),
                    address(0)
                );
                deal(address(_aFirst ? assetA : assetB), address(bridge), deposit1);
                vm.warp(block.timestamp + timediff * 1 days);
            }
            {
                movePrice(1e18, 0);
                // Deposit2
                bridge.convert(
                    _aFirst ? aztecAssetB : aztecAssetA,
                    emptyAsset,
                    _aFirst ? aztecAssetA : aztecAssetB,
                    emptyAsset,
                    deposit2,
                    1,
                    uint64(length2),
                    address(0)
                );
                deal(address(_aFirst ? assetB : assetA), address(bridge), deposit2);
                vm.warp(endTime);
            }
        }

        // Swap 1000 assetB for asset A. Will increase the value of asset A
        movePrice(0, 1000 ether);
        bridge.rebalanceAndFillUniswap();

        {
            // Finalise DCA position 0
            (uint256 acc, bool ready) = bridge.getAccumulated(0);
            (uint256 outputValueA, uint256 outputValueB, bool interactionComplete) = bridge.finalise(
                _aFirst ? aztecAssetA : aztecAssetB,
                emptyAsset,
                _aFirst ? aztecAssetB : aztecAssetA,
                emptyAsset,
                0,
                0
            );
            if (bridge.getDCA(0).end <= (block.timestamp / bridge.TICK_SIZE())) {
                assertTrue(ready, "Not ready to finalise 0");
                assertEq(outputValueA, acc, "outputValueA not matching");
                assertEq(outputValueB, 0, "Outputvalue B not zero");
                assertTrue(interactionComplete, "Interaction failed");

                if (_aFirst) {
                    uint256 aToBDirect = bridge.assetAInAssetB(deposit1, priceBefore, false);
                    assertGt(outputValueA, aToBDirect, "0 Received too little");
                    assetB.safeTransferFrom(address(bridge), address(this), outputValueA);
                } else {
                    uint256 bToADirect = bridge.assetBInAssetA(deposit1, priceBefore, false);
                    assertLt(outputValueA, bToADirect, "0 Received too much A");
                    assetA.safeTransferFrom(address(bridge), address(this), outputValueA);
                }
            } else {
                assertFalse(ready, "Ready to finalise 0");
                assertEq(outputValueA, 0, "outputValueA not zero");
                assertEq(outputValueB, 0, "Outputvalue B not zero");
                assertFalse(interactionComplete, "Interaction passed");
                printDCA(0);
            }
        }
        {
            // Finalise DCA position 1
            (uint256 acc, bool ready) = bridge.getAccumulated(1);
            (uint256 outputValueA, uint256 outputValueB, bool interactionComplete) = bridge.finalise(
                _aFirst ? aztecAssetB : aztecAssetA,
                emptyAsset,
                _aFirst ? aztecAssetA : aztecAssetB,
                emptyAsset,
                1,
                0
            );
            if (bridge.getDCA(1).end <= (block.timestamp / bridge.TICK_SIZE())) {
                assertTrue(ready, "Not ready to finalise 1");
                assertEq(outputValueA, acc, "outputValueA not matching");
                assertEq(outputValueB, 0, "Outputvalue B not zero");
                assertTrue(interactionComplete, "Interaction failed");
                if (!_aFirst) {
                    uint256 aToBDirect = bridge.assetAInAssetB(deposit2, priceBefore, false);
                    assertGt(outputValueA, aToBDirect, "1 Received too little");
                    assetB.safeTransferFrom(address(bridge), address(this), outputValueA);
                } else {
                    uint256 bToADirect = bridge.assetBInAssetA(deposit2, priceBefore, false);
                    assertLt(outputValueA, bToADirect, "1 Received too much A");
                    assetA.safeTransferFrom(address(bridge), address(this), outputValueA);
                }
            } else {
                assertFalse(ready, "Ready to finalise 0");
                assertEq(outputValueA, 0, "outputValueA not zero");
                assertEq(outputValueB, 0, "Outputvalue B not zero");
                assertFalse(interactionComplete, "Interaction passed");
                printDCA(1);
            }
        }

        {
            // Check that there are no available assets when everyone have exited
            // and that leftovers are manageble
            (uint256 availableA, uint256 availableB) = bridge.getAvailable();
            assertEq(availableA, 0, "Available A != 0");
            assertEq(availableB, 0, "Available B != 0");

            // TODO: Figure out a good way to do this.
            // assertLe(assetA.balanceOf(address(bridge)), deposit1 / 1e6, "too much left as 'dust'");
            // assertLe(assetB.balanceOf(address(bridge)), deposit2 / 1e6, "too much left as 'dust'");
        }
    }

    function testFuzzUniswapForceFillEth(
        uint256 _deposit1,
        uint256 _deposit2,
        bool _aFirst
    ) public {
        uint256 deposit1 = bound(_deposit1, 0.1e18, 1e21);
        uint256 deposit2 = bound(_deposit2, 0.1e18, 1e21);
        uint256 priceBefore = bridge.getPrice();

        aztecAssetB = AztecTypes.AztecAsset({
            id: 0,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.ETH
        });

        {
            refreshTs();
            // Deposit with asset A
            bridge.convert{value: _aFirst ? 0 : deposit1}(
                _aFirst ? aztecAssetA : aztecAssetB,
                emptyAsset,
                _aFirst ? aztecAssetB : aztecAssetA,
                emptyAsset,
                deposit1,
                0,
                7,
                address(0)
            );
            if (_aFirst) {
                deal(address(assetA), address(bridge), deposit1);
            }
            vm.warp(block.timestamp + 1 days);
        }
        {
            refreshTs();
            // Deposit2
            bridge.convert{value: _aFirst ? deposit2 : 0}(
                _aFirst ? aztecAssetB : aztecAssetA,
                emptyAsset,
                _aFirst ? aztecAssetA : aztecAssetB,
                emptyAsset,
                deposit2,
                1,
                7,
                address(0)
            );
            if (!_aFirst) {
                deal(address(assetA), address(bridge), deposit2);
            }
            vm.warp(block.timestamp + 9 days);
        }

        // Swap 1000 assetB for asset A. Will increase the value of asset A
        movePrice(0, 1000 ether);
        bridge.rebalanceAndFillUniswap();

        {
            // Finalise DCA position 0
            (uint256 acc, bool ready) = bridge.getAccumulated(0);
            uint256 ethBalBefore = address(this).balance;
            (uint256 outputValueA, uint256 outputValueB, bool interactionComplete) = bridge.finalise(
                _aFirst ? aztecAssetA : aztecAssetB,
                emptyAsset,
                _aFirst ? aztecAssetB : aztecAssetA,
                emptyAsset,
                0,
                0
            );
            assertTrue(ready);
            assertEq(outputValueA, acc, "outputValueA not matching");
            assertEq(outputValueB, 0, "Outputvalue B not zero");
            assertTrue(interactionComplete, "Interaction failed");

            if (_aFirst) {
                uint256 aToBDirect = bridge.assetAInAssetB(deposit1, priceBefore, false);
                assertGt(outputValueA, aToBDirect, "Received too little");
                assertEq(address(this).balance, ethBalBefore + outputValueA, "Incorrect balance");
            } else {
                uint256 bToADirect = bridge.assetBInAssetA(deposit1, priceBefore, false);
                assertLt(outputValueA, bToADirect, "Received too much A");
                assetA.safeTransferFrom(address(bridge), address(this), outputValueA);
            }
        }
        {
            // Finalise DCA position 1
            (uint256 acc, bool ready) = bridge.getAccumulated(1);
            uint256 ethBalBefore = address(this).balance;
            (uint256 outputValueA, uint256 outputValueB, bool interactionComplete) = bridge.finalise(
                _aFirst ? aztecAssetB : aztecAssetA,
                emptyAsset,
                _aFirst ? aztecAssetA : aztecAssetB,
                emptyAsset,
                1,
                0
            );
            assertTrue(ready);
            assertEq(outputValueA, acc, "outputValueA not matching");
            assertEq(outputValueB, 0, "Outputvalue B not zero");
            assertTrue(interactionComplete, "Interaction failed");
            if (!_aFirst) {
                uint256 aToBDirect = bridge.assetAInAssetB(deposit2, priceBefore, false);
                assertGt(outputValueA, aToBDirect, "Received too little");
                assertEq(address(this).balance, ethBalBefore + outputValueA, "Incorrect balance");
            } else {
                uint256 bToADirect = bridge.assetBInAssetA(deposit2, priceBefore, false);
                assertLt(outputValueA, bToADirect, "Received too much A");
                assetA.safeTransferFrom(address(bridge), address(this), outputValueA);
            }
        }

        {
            // Check that there are no available assets when everyone have exited
            // and that leftovers are manageble
            (uint256 availableA, uint256 availableB) = bridge.getAvailable();
            assertEq(availableA, 0, "Available A != 0");
            assertEq(availableB, 0, "Available B != 0");

            assertLe(assetA.balanceOf(address(bridge)), deposit1 / 1e6, "too much left as 'dust'");
            assertLe(assetB.balanceOf(address(bridge)), deposit2 / 1e6, "too much left as 'dust'");
        }
    }

    function testFuzzOutlineUniswapForceFill(
        uint256 _startPrice,
        uint256 _endPrice,
        uint256 _aDeposit,
        uint256 _bDeposit
    ) public {
        uint256 price = bound(_startPrice, 0.00001e18, 1e18);
        setPrice(price);

        {
            // Perform deposits
            uint256 aDeposit = bound(_aDeposit, 0.1e18, 1e24);
            uint256 bDeposit = bound(_bDeposit, 0.1e18, 1e21);

            bridge.convert(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, aDeposit, 0, 7, address(0));
            deal(address(assetA), address(bridge), aDeposit);
            vm.warp(block.timestamp + 1 days);

            refreshTs();
            bridge.convert(aztecAssetB, emptyAsset, aztecAssetA, emptyAsset, bDeposit, 1, 7, address(0));
            deal(address(assetB), address(bridge), bDeposit);
            vm.warp(block.timestamp + 9 days);
        }

        emit log_named_decimal_uint("A bal", assetA.balanceOf(address(bridge)), 18);
        emit log_named_decimal_uint("B bal", assetB.balanceOf(address(bridge)), 18);

        price = bound(_endPrice, 0.00001e18, 1e18);
        setPrice(price);

        printAvailable();
        {
            (int256 a, int256 b) = bridge.rebalanceTest(0, 0, bridge.getPrice(), true, false);
            assertEq(a, 0, "Rebal 0, A flow != 0");
            assertEq(b, 0, "Rebal 0, B flow != 0");

            printAvailable();
        }
        (uint256 _a, uint256 _b) = bridge.getAvailable();

        emit log_named_decimal_uint("A bal", assetA.balanceOf(address(bridge)), 18);
        emit log_named_decimal_uint("B bal", assetB.balanceOf(address(bridge)), 18);
        emit log("####");
        // If we have both assets. Match with them as much as possible.
        {
            if (_a > 0 && _b > 0) {
                emit log("Rebalance with all available");
                // There is something here were we throw away some token.

                (int256 a, int256 b) = bridge.rebalanceTest(_a, _b, bridge.getPrice(), true, false);
                emit log_named_decimal_int("Rebalance A", a, 18);
                emit log_named_decimal_int("Rebalance B", b, 18);
                printAvailable();

                assertGe(int256(_a), a, "Offer of A must cover needed");
                assertGe(int256(_b), b, "Offer of B must cover needed");

                // We also cannot be selling more than available
                assertLe(-int256(_a), a, "Selling more A than available");
                assertLe(-int256(_b), b, "Selling more B than available");

                // Ensure that we are not buying too much A or B
                assertLe(a, int256(0), "Bought too much A");
                assertLe(b, int256(0), "Bought too much B");
            }
        }

        emit log_named_decimal_uint("A bal", assetA.balanceOf(address(bridge)), 18);
        emit log_named_decimal_uint("B bal", assetB.balanceOf(address(bridge)), 18);
        emit log("----");

        // Only one asset should be back now. Take that and swap on uniswap for some "price", then rebalance with the received tokens.
        (uint256 _a2, uint256 _b2) = bridge.getAvailable();
        emit log_named_decimal_uint("A bal", assetA.balanceOf(address(bridge)), 18);
        emit log_named_decimal_uint("B bal", assetB.balanceOf(address(bridge)), 18);

        if (_a2 > 0) {
            emit log("Rebalance with A");
            // We need to do a swap from A to something else (for now we can fake an exchange and price)
            uint256 bOffer = bridge.assetAInAssetB(_a2, price, false);

            // Compute a price from the received b amount, round down to make A less valuable.
            uint256 _price = (bOffer * 1e18) / _a2;

            deal(address(assetB), address(this), assetB.balanceOf(address(this)) + bOffer);
            assetB.approve(address(bridge), bOffer);

            emit log_named_decimal_int("Offer     B", int256(bOffer), 18);
            (int256 a, int256 b) = bridge.rebalanceTest(0, bOffer, _price, true, true);
            emit log_named_decimal_int("Rebalance A", a, 18);
            emit log_named_decimal_int("Rebalance B", b, 18);
            assertGe(bOffer, uint256(b), "Offer must cover needed");
        }

        if (_b2 > 0) {
            emit log("Rebalance with B");
            uint256 aOffer = bridge.assetBInAssetA(_b2, price, false);

            // Compute a price from the amount we got from swap, round up, make A more valuable
            uint256 _price = (_b2 * 1e18 + aOffer - 1) / aOffer;

            deal(address(assetA), address(this), assetA.balanceOf(address(this)) + aOffer);
            assetA.approve(address(bridge), aOffer);

            emit log_named_decimal_int("Offer     A", int256(aOffer), 18);
            (int256 a, int256 b) = bridge.rebalanceTest(aOffer, 0, _price, true, true);
            emit log_named_decimal_int("Rebalance A", a, 18);
            emit log_named_decimal_int("Rebalance B", b, 18);
            assertGe(aOffer, uint256(a), "Offer must cover needed");
        }

        emit log_named_decimal_uint("A bal", assetA.balanceOf(address(bridge)), 18);
        emit log_named_decimal_uint("B bal", assetB.balanceOf(address(bridge)), 18);

        printAvailable();

        {
            // How did we end up with this?
            (uint256 a, uint256 b) = bridge.getAvailable();
            assertEq(a, 0, "Available A != 0");
            assertEq(b, 0, "Available B != 0");
        }
        printDCA(0);
        printDCA(1);

        {
            (uint256 acc, bool ready) = bridge.getAccumulated(0);
            assertTrue(ready);
            // Run the finalise and exit with funds.
            // Finalise DCA(0)

            (uint256 outputValueA, uint256 outputValueB, bool interactionComplete) = bridge.finalise(
                aztecAssetA,
                emptyAsset,
                aztecAssetB,
                emptyAsset,
                0,
                0
            );
            assertEq(outputValueB, 0, "Outputvalue B not zero");
            assertTrue(interactionComplete, "Interaction failed");
            emit log_named_decimal_uint("B bal", assetB.balanceOf(address(bridge)), 18);
            assetB.safeTransferFrom(address(bridge), address(this), outputValueA);
        }
        {
            (uint256 acc, bool ready) = bridge.getAccumulated(1);
            assertTrue(ready);
            // Run the finalise and exit with funds.
            (uint256 outputValueA, uint256 outputValueB, bool interactionComplete) = bridge.finalise(
                aztecAssetB,
                emptyAsset,
                aztecAssetA,
                emptyAsset,
                1,
                0
            );
            assertEq(outputValueB, 0, "Outputvalue B not zero");
            assertTrue(interactionComplete, "Interaction failed");
            emit log_named_decimal_uint("A bal", assetA.balanceOf(address(bridge)), 18);
            assetA.safeTransferFrom(address(bridge), address(this), outputValueA);

            // Have an issue with rounding, the accounting of A is 1 higher than actual A.
        }
    }

    // Test a flow with 1 DCA position over 7 days, ff 2 days into the run, offer enough to match
    function testFlow1_7DCA_2days_MoreThanEnough() public {
        uint256 price = bridge.getPrice();
        bridge.pokeNextTicks(10);

        uint256 startTick = block.timestamp / bridge.TICK_SIZE();

        uint256 depositUser1 = 700e18;

        bridge.convert(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, depositUser1, 0, 7, address(0));
        deal(address(assetA), address(bridge), 1000 ether);

        {
            (uint256 a, uint256 b) = bridge.getAvailable();
            assertEq(a, 0);
            assertEq(b, 0);
        }

        vm.warp(block.timestamp + 2 days);
        {
            // Check the available amount of funds
            (uint256 a, uint256 b) = bridge.getAvailable();
            assertEq(a, (depositUser1 / 7) * 2, "Available A not matching");
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
                TestDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 100e18, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
            }
        }

        uint256 dealAmount = 10e18;
        deal(address(assetB), address(this), dealAmount);
        assetB.approve(address(bridge), type(uint256).max);
        refreshTs();
        (int256 a, int256 b) = bridge.rebalanceAndfill(0, dealAmount);

        {
            // Check rabalance output values
            uint256 userBought = (depositUser1 / 7) * 2;
            // We compute the amount o
            uint256 _bSold = bridge.assetAInAssetB(userBought, price, true);
            assertEq(a, -(int256(userBought)), "User did not buy correct number of tokens tokens");
            assertEq(assetA.balanceOf(address(this)), uint256(-a), "Asset A balance not matching");
            assertEq(b, int256(_bSold), "User did not sell 0.1 eth");
            assertEq(assetB.balanceOf(address(bridge)), uint256(b), "Asset B balance not matching");
        }

        {
            for (uint256 i = 1; i < 3; i++) {
                uint256 userBought = (depositUser1 / 7);
                // Check tick[i]
                TestDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 0, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, i == 2 ? price : 0, "Price not matching");
                assertEq(tick.assetAToB.sold, userBought, "AToB sold not matching");
                assertEq(
                    tick.assetAToB.bought,
                    bridge.assetAInAssetB(userBought, price, true),
                    "AToB bought not matching"
                );
                assertEq(tick.assetBToA.sold, 0, "BToA sold not matching");
                assertEq(tick.assetBToA.bought, 0, "AToB bought not matching");
            }
        }

        {
            // Check the accumulated value of DCA(0)
            uint256 userBought = (depositUser1 / 7) * 2;
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, bridge.assetAInAssetB(userBought, price, true), "Accumulated not matching");
            assertFalse(ready, "Is ready");
        }
    }

    // Test a flow with 2 DCA position over 7 days, ff 2 days into the run, offer enough to match
    function testFlow2_7DCA_2days_MoreThanEnough() public {
        // Using the same price throughout this flow.
        uint256 price = bridge.getPrice();
        bridge.pokeNextTicks(10);
        uint256 startTick = block.timestamp / bridge.TICK_SIZE();

        // Deposit 700 A for selling over 7 days
        bridge.convert(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, 700 ether, 0, 7, address(0));
        vm.warp(block.timestamp + 1 days);
        refreshTs();
        bridge.convert(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, 1400 ether, 1, 7, address(0));
        deal(address(assetA), address(bridge), 2100 ether);

        {
            (uint256 a, uint256 b) = bridge.getAvailable();
            assertEq(a, 100 ether);
            assertEq(b, 0);
        }

        vm.warp(block.timestamp + 2 days);
        {
            // Check the available amount of funds
            (uint256 a, uint256 b) = bridge.getAvailable();
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
                TestDCABridge.Tick memory tick = bridge.getTick(startTick + 1);
                assertEq(tick.availableA, 100e18, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, price, "Price not matching");
            }
            for (uint256 i = 2; i < 8; i++) {
                // Check tick[i]
                TestDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 300e18, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
            }
            {
                TestDCABridge.Tick memory tick = bridge.getTick(startTick + 8);
                assertEq(tick.availableA, 200e18, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
            }
        }

        deal(address(assetB), address(this), 1000 ether);
        assetB.approve(address(bridge), type(uint256).max);
        refreshTs();
        (int256 a, int256 b) = bridge.rebalanceAndfill(0, 10 ether);

        {
            // Check rabalance output values
            assertEq(a, -(100e18 + 300e18 * 2), "User did not buy 700 tokens");
            assertEq(assetA.balanceOf(address(this)), uint256(-a), "Asset A balance not matching");
            int256 expB = int256(bridge.assetAInAssetB(700e18, price, true));
            assertEq(b, expB, "User did not sell 0.6 eth");
            assertEq(assetB.balanceOf(address(bridge)), uint256(b), "Asset B balance not matching");
        }

        {
            {
                // Check tick[1]
                TestDCABridge.Tick memory tick = bridge.getTick(startTick + 1);
                assertEq(tick.availableA, 0, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, price, "Price not matching");
                assertEq(tick.assetAToB.sold, 100e18, "AToB sold not matching");
                assertEq(tick.assetAToB.bought, bridge.assetAInAssetB(100e18, price, true), "AToB bought not matching");
                assertEq(tick.assetBToA.sold, 0, "BToA sold not matching");
                assertEq(tick.assetBToA.bought, 0, "AToB bought not matching");
            }
            for (uint256 i = 2; i < 4; i++) {
                emit log_uint(i);
                // Check tick[i]
                TestDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 0, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, i == 3 ? price : 0, "Price not matching");
                assertEq(tick.assetAToB.sold, 300e18, "AToB sold not matching");
                assertEq(tick.assetAToB.bought, bridge.assetAInAssetB(300e18, price, true), "AToB bought not matching");
                assertEq(tick.assetBToA.sold, 0, "BToA sold not matching");
                assertEq(tick.assetBToA.bought, 0, "AToB bought not matching");
            }
        }

        {
            // Check the accumulated value of DCA(0), accumulated 3 days
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, bridge.assetAInAssetB(300e18, price, true), "Accumulated not matching");
            assertFalse(ready, "Is ready");
        }

        {
            // Check the accumulated value of DCA(1)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(1);
            assertEq(accumulated, bridge.assetAInAssetB(400e18, price, true), "Accumulated not matching");
            assertFalse(ready, "Is ready");
        }
    }

    // Test a flow with 1 DCA position over 7 days, ff 8 days into the run, offer enough to match
    function testFlow1_7DCA_8days_MoreThanEnough() public {
        uint256 price = bridge.getPrice();
        bridge.pokeNextTicks(10);
        uint256 startTick = block.timestamp / bridge.TICK_SIZE();
        // Deposit 700 A for selling over 7 days
        bridge.convert(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, 700 ether, 0, 7, address(0));
        deal(address(assetA), address(bridge), 1000 ether);

        {
            (uint256 a, uint256 b) = bridge.getAvailable();
            assertEq(a, 0);
            assertEq(b, 0);
        }

        vm.warp(block.timestamp + 8 days);
        {
            // Check the available amount of funds
            (uint256 a, uint256 b) = bridge.getAvailable();
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
                TestDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 100 ether, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
            }
        }

        deal(address(assetB), address(this), 1000 ether);
        assetB.approve(address(bridge), type(uint256).max);
        refreshTs();
        (int256 a, int256 b) = bridge.rebalanceAndfill(0, 10 ether);

        {
            // Check rabalance output values
            assertEq(a, -700 ether, "User did not buy 700 tokens");
            assertEq(assetA.balanceOf(address(this)), uint256(-a), "Asset A balance not matching");
            assertEq(b, int256(bridge.assetAInAssetB(700e18, price, true)), "User did not sell 0.7 eth");
            assertEq(assetB.balanceOf(address(bridge)), uint256(b), "Asset B balance not matching");
        }

        {
            for (uint256 i = 1; i < 8; i++) {
                // Check tick[i]
                TestDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 0, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
                assertEq(tick.assetAToB.sold, 100e18, "AToB sold not matching");
                assertEq(tick.assetAToB.bought, bridge.assetAInAssetB(100e18, price, true), "AToB bought not matching");
                assertEq(tick.assetBToA.sold, 0, "BToA sold not matching");
                assertEq(tick.assetBToA.bought, 0, "AToB bought not matching");
            }
        }

        {
            // Check the accumulated value of DCA(0)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, bridge.assetAInAssetB(700e18, price, true), "Accumulated not matching");
            assertTrue(ready, "Is ready");
        }
    }

    // Test a flow with 1 DCA position over 7 days, ff 8 days into the run, offer too little to match
    function testFlow1_7DCA_8days_OfferTooLittle() public {
        uint256 price = bridge.getPrice();
        bridge.pokeNextTicks(10);
        uint256 startTick = block.timestamp / bridge.TICK_SIZE();
        // Deposit 700 A for selling over 7 days
        bridge.convert(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, 700 ether, 0, 7, address(0));
        deal(address(assetA), address(bridge), 1000 ether);

        {
            (uint256 a, uint256 b) = bridge.getAvailable();
            assertEq(a, 0);
            assertEq(b, 0);
        }

        vm.warp(block.timestamp + 8 days);
        {
            // Check the available amount of funds
            (uint256 a, uint256 b) = bridge.getAvailable();
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
                TestDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 100 ether, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
            }
        }

        deal(address(assetB), address(this), 1000 ether);
        assetB.approve(address(bridge), type(uint256).max);
        refreshTs();
        (int256 a, int256 b) = bridge.rebalanceAndfill(0, 0.15 ether);

        {
            // Check rabalance output values
            // We go through two ticks, 100 from first
            uint256 assetBPayment1 = bridge.assetAInAssetB(100e18, price, true);
            uint256 bLeft = 0.15e18 - assetBPayment1;
            uint256 aBought = bridge.assetBInAssetA(bLeft, price, false);
            uint256 assetBPayment2 = bridge.assetAInAssetB(aBought, price, true);

            assertEq(a, -int256(100e18 + aBought), "User did not buy matching tokens");
            assertEq(assetA.balanceOf(address(this)), uint256(-a), "Asset A balance not matching");
            assertEq(b, int256(assetBPayment1 + assetBPayment2), "User did not sell matching eth");
            assertEq(assetB.balanceOf(address(bridge)), uint256(b), "Asset B balance not matching");
        }

        {
            // Check tick 1
            TestDCABridge.Tick memory tick = bridge.getTick(startTick + 1);
            assertEq(tick.availableA, 0, "Available A not matching");
            assertEq(tick.availableB, 0, "Available B not matching");
            assertEq(tick.priceAToB, 0, "Price not matching");
            assertEq(tick.assetAToB.sold, 100 ether, "AToB sold not matching");
            assertEq(tick.assetAToB.bought, bridge.assetAInAssetB(100e18, price, true), "AToB bought not matching");
            assertEq(tick.assetBToA.sold, 0, "BToA sold not matching");
            assertEq(tick.assetBToA.bought, 0, "AToB bought not matching");
        }

        {
            uint256 bLeft = 0.15e18 - bridge.assetAInAssetB(100e18, price, true);
            uint256 aBought = bridge.assetBInAssetA(bLeft, price, false);
            uint256 assetBPayment2 = bridge.assetAInAssetB(aBought, price, true);

            // Check tick 2
            TestDCABridge.Tick memory tick = bridge.getTick(startTick + 2);
            assertEq(tick.availableA, 100e18 - aBought, "Available A not matching");
            assertEq(tick.availableB, 0, "Available B not matching");
            assertEq(tick.priceAToB, 0, "Price not matching");
            assertEq(tick.assetAToB.sold, aBought, "AToB sold not matching");
            assertEq(tick.assetAToB.bought, assetBPayment2, "AToB bought not matching");
            assertEq(tick.assetBToA.sold, 0, "BToA sold not matching");
            assertEq(tick.assetBToA.bought, 0, "AToB bought not matching");
        }
        {
            for (uint256 i = 3; i < 8; i++) {
                // Check tick[i]
                TestDCABridge.Tick memory tick = bridge.getTick(startTick + i);
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
            uint256 assetBPayment1 = bridge.assetAInAssetB(100e18, price, true);
            uint256 bLeft = 0.15e18 - assetBPayment1;
            uint256 aBought = bridge.assetBInAssetA(bLeft, price, false);
            uint256 assetBPayment2 = bridge.assetAInAssetB(aBought, price, true);

            // Check the accumulated value of DCA(0)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, assetBPayment1 + assetBPayment2, "Accumulated not matching");
            assertFalse(ready, "Is ready");
        }
    }

    function testBiFlowPerfectMatchERC20() public {
        uint256 price = bridge.getPrice();
        bridge.pokeNextTicks(10);
        uint256 startTick = block.timestamp / bridge.TICK_SIZE();
        // Deposit 700 A for selling over 7 days
        bridge.convert(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, 700 ether, 0, 7, address(0));
        bridge.convert(
            aztecAssetB,
            emptyAsset,
            aztecAssetA,
            emptyAsset,
            bridge.assetAInAssetB(700e18, price, true),
            1,
            7,
            address(0)
        );
        deal(address(assetA), address(bridge), 700e18);
        deal(address(assetB), address(bridge), bridge.assetAInAssetB(700e18, price, true));

        {
            (uint256 a, uint256 b) = bridge.getAvailable();
            assertEq(a, 0);
            assertEq(b, 0);
        }

        vm.warp(block.timestamp + 8 days);
        {
            // Check the available amount of funds
            (uint256 a, uint256 b) = bridge.getAvailable();
            assertEq(a, 700e18, "Available A not matching");
            assertEq(b, bridge.assetAInAssetB(700e18, price, true), "Available B not matching");
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
                TestDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 100e18, "Available A not matching");
                assertEq(tick.availableB, bridge.assetAInAssetB(100e18, price, true), "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
            }
        }

        refreshTs();
        (int256 a, int256 b) = bridge.rebalanceAndfill(0, 0);

        {
            // Check rabalance output values
            assertEq(a, 0 ether, "User did not buy 0 tokens");
            assertEq(b, 0 ether, "User did not sell 0 eth");
        }
        {
            for (uint256 i = 1; i < 8; i++) {
                // Check tick[i]
                uint256 _b = bridge.assetAInAssetB(100e18, price, true);

                TestDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 0, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
                assertEq(tick.assetAToB.sold, 100e18, "AToB sold not matching");
                assertEq(tick.assetAToB.bought, _b, "AToB bought not matching");
                assertEq(tick.assetBToA.sold, _b, "BToA sold not matching");
                assertEq(tick.assetBToA.bought, 100e18, "AToB bought not matching");
            }
        }

        {
            // Check the accumulated value of DCA(0)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, bridge.assetAInAssetB(700e18, price, true), "Accumulated not matching");
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
            assertEq(outputValueA, bridge.assetAInAssetB(700e18, price, true), "OutputValue A not matching");
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

    function testBiFlowPerfectMatchEth() public {
        uint256 price = bridge.getPrice();
        uint256 _b = bridge.assetAInAssetB(700e18, price, true);

        aztecAssetB = AztecTypes.AztecAsset({
            id: 0,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.ETH
        });

        bridge.pokeNextTicks(10);
        uint256 startTick = block.timestamp / bridge.TICK_SIZE();
        // Deposit 700 A for selling over 7 days
        bridge.convert(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, 700 ether, 0, 7, address(0));
        bridge.convert{value: _b}(aztecAssetB, emptyAsset, aztecAssetA, emptyAsset, _b, 1, 7, address(0));
        deal(address(assetA), address(bridge), 700e18);
        deal(address(assetB), address(bridge), _b);

        {
            (uint256 a, uint256 b) = bridge.getAvailable();
            assertEq(a, 0);
            assertEq(b, 0);
        }

        vm.warp(block.timestamp + 8 days);
        {
            // Check the available amount of funds
            (uint256 a, uint256 b) = bridge.getAvailable();
            assertEq(a, 700e18, "Available A not matching");
            assertEq(b, _b, "Available B not matching");
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
                TestDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 100e18, "Available A not matching");
                assertEq(tick.availableB, _b / 7, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
            }
        }

        refreshTs();
        (int256 a, int256 b) = bridge.rebalanceAndfill(0, 0);

        {
            // Check rabalance output values
            assertEq(a, 0 ether, "User did not buy 0 tokens");
            assertEq(b, 0 ether, "User did not sell 0 eth");
        }
        {
            for (uint256 i = 1; i < 8; i++) {
                // Check tick[i]
                TestDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 0, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
                assertEq(tick.assetAToB.sold, 100e18, "AToB sold not matching");
                assertEq(
                    tick.assetAToB.bought,
                    bridge.assetAInAssetB(100e18, price, false),
                    "AToB bought not matching"
                );
                assertEq(tick.assetBToA.sold, bridge.assetAInAssetB(100e18, price, false), "BToA sold not matching");
                assertEq(tick.assetBToA.bought, 100e18, "AToB bought not matching");
            }
        }

        {
            // Check the accumulated value of DCA(0)
            (uint256 accumulated, bool ready) = bridge.getAccumulated(0);
            assertEq(accumulated, _b, "Accumulated not matching");
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
            uint256 ethBalBefore = address(this).balance;
            (uint256 outputValueA, uint256 outputValueB, bool interactionComplete) = bridge.finalise(
                aztecAssetA,
                emptyAsset,
                aztecAssetB,
                emptyAsset,
                0,
                0
            );
            assertEq(outputValueA, _b, "OutputValue A not matching");
            assertEq(outputValueB, 0, "Outputvalue B not zero");
            assertTrue(interactionComplete, "Interaction failed");

            assertEq(address(this).balance, ethBalBefore + outputValueA, "Eth balance not matching");
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
        uint256 price = bridge.getPrice();
        bridge.pokeNextTicks(10);
        uint256 startTick = block.timestamp / bridge.TICK_SIZE();
        bridge.convert(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, 1400 ether, 0, 7, address(0));
        deal(address(assetA), address(bridge), 1400e18);

        vm.warp(block.timestamp + 1 days);

        refreshTs();
        bridge.convert(aztecAssetB, emptyAsset, aztecAssetA, emptyAsset, 0.7 ether, 1, 7, address(0));
        deal(address(assetB), address(bridge), 0.7e18);

        {
            (uint256 a, uint256 b) = bridge.getAvailable();
            assertEq(a, 200e18);
            assertEq(b, 0);
        }

        vm.warp(block.timestamp + 8 days);
        {
            // Check the available amount of funds
            (uint256 a, uint256 b) = bridge.getAvailable();
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
                TestDCABridge.Tick memory tick = bridge.getTick(startTick + 1);
                assertEq(tick.availableA, 200e18, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, price, "Price not matching");
            }
            for (uint256 i = 2; i < 8; i++) {
                // Check tick[i]
                TestDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 200e18, "Available A not matching");
                assertEq(tick.availableB, 0.1e18, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
            }
            {
                // Check tick[8]
                TestDCABridge.Tick memory tick = bridge.getTick(startTick + 8);
                assertEq(tick.availableA, 0, "Available A not matching");
                assertEq(tick.availableB, 0.1e18, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
            }
        }

        // Some calls rebalance
        movePrice(1e18, 0); // This is probably better for full cover, but why does it mess with the bridge accounting :eyes:

        {
            (int256 a, int256 b) = bridge.rebalanceAndfill(0, 0);
            // Check rabalance output values
            assertEq(a, 0 ether, "User did not buy 0 tokens");
            assertEq(b, 0 ether, "User did not sell 0 eth");
        }

        Sums memory sums;

        {
            {
                // Check tick[1]
                TestDCABridge.Tick memory tick = bridge.getTick(startTick + 1);
                assertEq(tick.availableA, 200e18, "Available A not matching");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, price, "Price not matching");
                assertEq(tick.assetAToB.sold, 0, "AToB sold not matching");
                assertEq(tick.assetAToB.bought, 0, "AToB bought not matching");
                assertEq(tick.assetBToA.sold, 0, "BToA sold not matching");
                assertEq(tick.assetBToA.bought, 0, "AToB bought not matching");
            }
            for (uint256 i = 2; i < 8; i++) {
                // Because of the price change, need to interpolate
                uint256 interpolatedPrice;
                {
                    TestDCABridge.Tick memory tick = bridge.getTick(startTick + 1);
                    int256 slope = (int256(bridge.getPrice()) - int256(uint256(tick.priceAToB))) /
                        int256(block.timestamp - uint256(tick.priceUpdated));
                    uint256 dt = (startTick + i) *
                        bridge.TICK_SIZE() +
                        bridge.TICK_SIZE() /
                        2 -
                        uint256(tick.priceUpdated);
                    interpolatedPrice = uint256(int256(uint256(tick.priceAToB)) + slope * int256(dt));
                }
                uint256 _a = bridge.assetBInAssetA(0.1e18, interpolatedPrice, false);
                sums.summedA += _a;
                sums.summedB += 0.1e18;
                sums.summedBInv += bridge.assetAInAssetB(200e18 - _a, bridge.getPrice(), true);
                // Check tick[i]
                TestDCABridge.Tick memory tick = bridge.getTick(startTick + i);
                assertEq(tick.availableA, 200e18 - _a, "Available A not matching 2<8");
                assertEq(tick.availableB, 0, "Available B not matching");
                assertEq(tick.priceAToB, 0, "Price not matching");
                assertEq(tick.assetAToB.sold, _a, "AToB sold not matching");
                assertEq(tick.assetAToB.bought, 0.1e18, "AToB bought not matching");
                assertEq(tick.assetBToA.sold, 0.1e18, "BToA sold not matching");
                assertEq(tick.assetBToA.bought, _a, "AToB bought not matching");
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
            assertEq(accumulated, sums.summedA, "Accumulated not matching");
            assertFalse(ready, "Is ready");
        }

        // Someone comes in an rebalance the alst by selling eth to the bridge;
        deal(address(assetB), address(this), 1 ether);
        assetB.approve(address(bridge), 1 ether);
        {
            (int256 a2, int256 b2) = bridge.rebalanceAndfill(0, 1 ether);
            price = bridge.getPrice();

            assertEq(a2, -int256(1400e18 - sums.summedA), "User did not buy matching tokens");
            // 200 A from the day before, rest across split.
            assertEq(
                b2,
                int256(sums.summedBInv + bridge.assetAInAssetB(200e18, price, true)),
                "User did not sell matching tokens"
            );
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
            uint256 _b = bridge.assetAInAssetB(200e18, price, true);
            uint256 expectedOutputA = sums.summedB + sums.summedBInv + _b;

            assertEq(outputValueA, expectedOutputA, "OutputValue A not matching");
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
            // Values are zero because interaction is not ready.
            assertEq(outputValueA, 0, "OutputValue A not zero");
            assertEq(outputValueB, 0, "Outputvalue B not zero");
            assertFalse(interactionComplete, "Interaction ready");

            assetA.safeTransferFrom(address(bridge), address(this), outputValueA);
        }
    }

    function printDCA(uint256 _nonce) public returns (TestDCABridge.DCA memory) {
        (uint256 accumulated, bool ready) = bridge.getAccumulated(_nonce);
        TestDCABridge.DCA memory dca = bridge.getDCA(_nonce);
        emit log_named_uint("DCA at nonce", _nonce);
        emit log_named_decimal_uint("Total ", dca.total, 18);
        emit log_named_uint("start ", dca.start);
        emit log_named_uint("end   ", dca.end);
        emit log_named_decimal_uint(dca.assetA ? "accumB" : "accumA", accumulated, 18);
        if (ready) {
            emit log("Ready for harvest");
        }

        return dca;
    }

    function printAvailable() public {
        (uint256 a, uint256 b) = bridge.getAvailable();
        emit log_named_decimal_uint("Available A", a, 18);
        emit log_named_decimal_uint("Available B", b, 18);
    }

    function printTick(uint256 _tick) public returns (TestDCABridge.Tick memory) {
        TestDCABridge.Tick memory tick = bridge.getTick(_tick);

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

        if (_amountAToB > 0) {
            deal(address(assetA), address(this), _amountAToB);
            assetA.approve(address(uniRouter), type(uint256).max);

            uint256 b = uniRouter.exactInput(
                ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(address(assetA), uint24(100), USDC, uint24(500), address(assetB)),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: _amountAToB,
                    amountOutMinimum: 0
                })
            );

            uint256 price = (b * 1e18) / _amountAToB;
            setPrice(price);
        }

        if (_amountBToA > 0) {
            deal(address(assetB), address(this), _amountBToA);
            assetB.approve(address(uniRouter), type(uint256).max);

            uint256 a = uniRouter.exactInput(
                ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(address(assetB), uint24(500), USDC, uint24(100), address(assetA)),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: _amountBToA,
                    amountOutMinimum: 0
                })
            );
            uint256 price = (_amountBToA * 1e18 + a - 1) / a;
            setPrice(price);
        }
    }
}
