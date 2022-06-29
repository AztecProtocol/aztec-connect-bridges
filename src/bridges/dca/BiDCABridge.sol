// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";

import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";

import {IWETH} from "../../interfaces/IWETH.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Test} from "forge-std/Test.sol";

/**
 * @notice Very rough draft reference implementation of DCA
 * @dev DO NOT USE THIS IS PRODUCTION, UNFINISHED CODE.
 */

library Muldiv {
    // Used when computing how much you get
    function mulDivDown(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require(denominator != 0 && (x == 0 || (x * y) / x == y))
            if iszero(and(iszero(iszero(denominator)), or(iszero(x), eq(div(z, x), y)))) {
                revert(0, 0)
            }

            // Divide z by the denominator.
            z := div(z, denominator)
        }
    }

    // Used when computing how much to pay
    function mulDivUp(
        uint256 x,
        uint256 y,
        uint256 denominator
    ) internal pure returns (uint256 z) {
        assembly {
            // Store x * y in z for now.
            z := mul(x, y)

            // Equivalent to require(denominator != 0 && (x == 0 || (x * y) / x == y))
            if iszero(and(iszero(iszero(denominator)), or(iszero(x), eq(div(z, x), y)))) {
                revert(0, 0)
            }

            // First, divide z - 1 by the denominator and add 1.
            // We allow z - 1 to underflow if z is 0, because we multiply the
            // end result by 0 if z is zero, ensuring we return 0 if z is zero.
            z := mul(iszero(iszero(z)), add(div(sub(z, 1), denominator), 1))
        }
    }
}

abstract contract BiDCABridge is BridgeBase, Test {
    using SafeERC20 for IERC20;
    using Muldiv for uint256;

    error PositionAlreadyExists();

    struct RebalanceValues {
        uint256 currentPrice;
        uint256 oldestTickAvailableA;
        uint256 oldestTickAvailableB;
        uint256 offerAInB;
        uint256 offerBInA;
        uint256 protocolSoldA;
        uint256 protocolSoldB;
        uint256 protocolBoughtA;
        uint256 protocolBoughtB;
        uint256 lastUsedPrice;
        uint256 lastUsedPriceTs;
    }

    struct DCA {
        uint256 total;
        uint32 start;
        uint32 end;
        bool assetA;
    }

    struct SubTick {
        uint256 sold;
        uint256 bought;
    }

    struct Tick {
        uint256 availableA;
        uint256 availableB;
        uint16 poke;
        SubTick assetAToB;
        SubTick assetBToA;
        uint256 priceAToB;
        uint256 priceUpdated;
    }

    IWETH internal constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    IERC20 public immutable ASSET_A;
    IERC20 public immutable ASSET_B;

    uint256 public immutable TICK_SIZE;

    uint256 public oldestTickAvailableA;
    uint256 public lastTickAvailableB;

    // day => Tick
    mapping(uint256 => Tick) public ticks;
    // nonce => DCA
    mapping(uint256 => DCA) public dcas;

    constructor(
        address _rollupProcessor,
        address _assetA,
        address _assetB,
        uint256 _tickSize
    ) BridgeBase(_rollupProcessor) {
        ASSET_A = IERC20(_assetA);
        ASSET_B = IERC20(_assetB);
        TICK_SIZE = _tickSize;

        IERC20(_assetA).safeApprove(_rollupProcessor, type(uint256).max);
        IERC20(_assetB).safeApprove(_rollupProcessor, type(uint256).max);
    }

    receive() external payable {}

    function pokeNextTicks(uint256 _ticks) public {
        uint256 nextTick = ((block.timestamp + TICK_SIZE - 1) / TICK_SIZE);
        pokeTicks(nextTick, _ticks);
    }

    function pokeTicks(uint256 _startTick, uint256 _ticks) public {
        for (uint256 i = _startTick; i < _startTick + _ticks; i++) {
            ticks[i].poke++;
        }
    }

    function rebalanceAndfill(uint256 _offerA, uint256 _offerB) public returns (int256, int256) {
        (int256 flowA, int256 flowB) = _rebalanceAndfill(_offerA, _offerB, getPrice(), false);
        if (flowA > 0) {
            ASSET_A.safeTransferFrom(msg.sender, address(this), uint256(flowA));
        } else if (flowA < 0) {
            ASSET_A.safeTransfer(msg.sender, uint256(-flowA));
        }

        if (flowB > 0) {
            ASSET_B.safeTransferFrom(msg.sender, address(this), uint256(flowB));
        } else if (flowB < 0) {
            ASSET_B.safeTransfer(msg.sender, uint256(-flowB));
        }

        return (flowA, flowB);
    }

    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64 _ticks,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256,
            uint256,
            bool
        )
    {
        address inputAssetAddress = _inputAssetA.erc20Address;
        address outputAssetAddress = _outputAssetA.erc20Address;

        if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
            WETH.deposit{value: _inputValue}();
            inputAssetAddress = address(WETH);
        }
        if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
            outputAssetAddress = address(WETH);
        }

        if (inputAssetAddress != address(ASSET_A) && inputAssetAddress != address(ASSET_B)) {
            revert ErrorLib.InvalidInputA();
        }
        bool assetA = inputAssetAddress == address(ASSET_A);

        if (outputAssetAddress != (assetA ? address(ASSET_B) : address(ASSET_A))) {
            revert ErrorLib.InvalidOutputA();
        }
        if (dcas[_interactionNonce].start != 0) {
            revert PositionAlreadyExists();
        }

        _deposit(_interactionNonce, _inputValue, _ticks, assetA);
        return (0, 0, true);
    }

    function finalise(
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _interactionNonce,
        uint64
    )
        external
        payable
        virtual
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256,
            bool interactionComplete
        )
    {
        uint256 accumulated;
        (accumulated, interactionComplete) = getAccumulated(_interactionNonce);

        if (interactionComplete) {
            bool toEth;

            address outputAssetAddress = _outputAssetA.erc20Address;
            if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                toEth = true;
                outputAssetAddress = address(WETH);
            }

            if (outputAssetAddress != (dcas[_interactionNonce].assetA ? address(ASSET_B) : address(ASSET_A))) {
                revert ErrorLib.InvalidOutputA();
            }

            outputValueA = accumulated;
            delete dcas[_interactionNonce];

            if (toEth) {
                WETH.withdraw(accumulated);
                IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(_interactionNonce);
            }
        }
    }

    /**
     * @notice The brice of A in B, e.g., 0.1 would mean 10 A = 1 B
     */
    function getPrice() public virtual returns (uint256);

    function assetAInAssetB(
        uint256 _amount,
        uint256 _priceAToB,
        bool _up
    ) public pure returns (uint256) {
        if (_up) {
            return _amount.mulDivUp(_priceAToB, 1e18);
        }
        return _amount.mulDivDown(_priceAToB, 1e18);
    }

    function assetBInAssetA(
        uint256 _amount,
        uint256 _priceAToB,
        bool _up
    ) public pure returns (uint256) {
        if (_up) {
            return _amount.mulDivUp(1e18, _priceAToB);
        }
        return _amount.mulDivDown(1e18, _priceAToB);
    }

    function getTick(uint256 _day) public view returns (Tick memory) {
        return ticks[_day];
    }

    function getDCA(uint256 _nonce) public view returns (DCA memory) {
        return dcas[_nonce];
    }

    function getAvailable() public view returns (uint256 availableA, uint256 availableB) {
        uint256 start = _lastUsedTick(oldestTickAvailableA, lastTickAvailableB);
        uint256 lastTick = block.timestamp / TICK_SIZE;
        for (uint256 i = start; i <= lastTick; i++) {
            availableA += ticks[i].availableA;
            availableB += ticks[i].availableB;
        }
    }

    function getAccumulated(uint256 _nonce) public view returns (uint256 accumulated, bool ready) {
        DCA storage dca = dcas[_nonce];
        uint256 start = dca.start;
        uint256 end = dca.end;
        uint256 tickAmount = dca.total / (end - start);
        bool assetA = dca.assetA;

        ready = true;

        for (uint256 i = start; i < end; i++) {
            Tick storage tick = ticks[i];
            (uint256 available, uint256 sold, uint256 bought) = assetA
                ? (tick.availableA, tick.assetAToB.sold, tick.assetAToB.bought)
                : (tick.availableB, tick.assetBToA.sold, tick.assetBToA.bought);
            ready = ready && available == 0 && sold > 0;
            accumulated += sold == 0 ? 0 : (bought * tickAmount) / (sold + available);
        }
    }

    function _deposit(
        uint256 _nonce,
        uint256 _amount,
        uint256 _ticks,
        bool _assetA
    ) internal {
        uint256 nextTick = ((block.timestamp + TICK_SIZE - 1) / TICK_SIZE);
        if (_assetA && oldestTickAvailableA == 0) {
            oldestTickAvailableA = nextTick;
        }
        if (!_assetA && lastTickAvailableB == 0) {
            lastTickAvailableB = nextTick;
        }
        // Update prices of today
        ticks[nextTick - 1].priceAToB = getPrice();
        ticks[nextTick - 1].priceUpdated = block.timestamp;

        uint240 tickAmount = _toU240(_amount / _ticks);
        for (uint256 i = nextTick; i < nextTick + _ticks; i++) {
            if (_assetA) {
                ticks[i].availableA += tickAmount;
            } else {
                ticks[i].availableB += tickAmount;
            }
        }
        dcas[_nonce] = DCA({
            total: _toU128(_amount),
            start: _toU32(nextTick),
            end: _toU32(nextTick + _ticks),
            assetA: _assetA
        });
    }

    /**
     * @notice Rebalances and trades into unfilled ticks.
     * Will rebalance based on own assets first, before allowing the ticks to be filled by external assets
     */
    function _rebalanceAndfill(
        uint256 _offerA,
        uint256 _offerB,
        uint256 _currentPrice,
        bool _self
    ) internal returns (int256, int256) {
        RebalanceValues memory vars;
        vars.currentPrice = _currentPrice;

        // Cache the oldest ticks, and compute earliest tick for the loop
        uint256 oldestTickA = vars.oldestTickAvailableA = oldestTickAvailableA;
        uint256 oldestTickB = vars.oldestTickAvailableB = lastTickAvailableB;
        uint256 oldestTick = _lastUsedTick(oldestTickA, oldestTickB);

        // Cache last used price for use in case we don't have a fresh price.
        vars.lastUsedPrice = ticks[oldestTick].priceAToB;
        vars.lastUsedPriceTs = ticks[oldestTick].priceUpdated;
        if (vars.lastUsedPrice == 0) {
            uint256 lookBack = oldestTick;
            while (vars.lastUsedPrice == 0) {
                lookBack--;
                vars.lastUsedPrice = ticks[lookBack].priceAToB;
                vars.lastUsedPriceTs = ticks[lookBack].priceUpdated;
            }
        }

        // Compute values in opposite asset to do comparisons. Round down.
        vars.offerAInB = assetAInAssetB(_offerA, vars.currentPrice, false);
        vars.offerBInA = assetBInAssetA(_offerB, vars.currentPrice, false);

        uint256 nextTick = ((block.timestamp + TICK_SIZE - 1) / TICK_SIZE);
        for (uint256 i = oldestTick; i < nextTick; i++) {
            // Load a cache
            Tick memory tick = ticks[i];

            // Rebalance the tick using available balances
            if (tick.availableA > 0 && tick.availableB > 0) {
                uint256 price = tick.priceAToB;

                // If a price is stored, update the last used price and timestamp. Otherwise intrapolate.
                if (price > 0) {
                    vars.lastUsedPrice = price;
                    vars.lastUsedPriceTs = tick.priceUpdated;
                } else {
                    int256 slope = (int256(vars.currentPrice) - int256(vars.lastUsedPrice)) /
                        int256(block.timestamp - vars.lastUsedPriceTs);
                    uint256 dt = i * TICK_SIZE + TICK_SIZE / 2 - vars.lastUsedPriceTs;
                    int256 _price = int256(vars.lastUsedPrice) + slope * int256(dt);
                    if (_price <= 0) {
                        price = 0;
                    } else {
                        price = uint256(_price);
                    }
                }

                // To compare we need same basis. Compute value of the available A in base B. Round down
                uint256 buyableBWithA = assetAInAssetB(tick.availableA, price, false);

                // If more value in A than B, we can use all available B. Otherwise, use all available A
                if (buyableBWithA > tick.availableB) {
                    // The value of all available B in asset A. Round down
                    uint256 buyableAWithB = assetBInAssetA(tick.availableB, price, false);

                    // Update Asset A
                    tick.assetAToB.sold += buyableAWithB;
                    tick.assetAToB.bought += tick.availableB;

                    // Update Asset B
                    tick.assetBToA.bought += buyableAWithB;
                    tick.assetBToA.sold += tick.availableB;

                    // Update available values
                    tick.availableA -= buyableAWithB;
                    tick.availableB = 0;
                } else {
                    // We got more B than A, fill everything in A and part of B

                    // Update Asset B
                    tick.assetBToA.sold += buyableBWithA;
                    tick.assetBToA.bought += tick.availableA;

                    // Update Asset A
                    tick.assetAToB.bought += buyableBWithA;
                    tick.assetAToB.sold += tick.availableA;

                    // Update available values
                    tick.availableA = 0;
                    tick.availableB -= buyableBWithA;
                }
            }

            // Only a problem when we are trading between assets we have ourselves.
            // Below is used to trade with external parties. Note that if own available assets are used, there are nothing ensuring that we have the assets that is matched.

            // If there is still available B, use the offer with A to buy it
            if (vars.offerAInB > 0 && tick.availableB > 0) {
                uint256 amountBSold = vars.offerAInB;
                // We cannot buy more than available
                if (vars.offerAInB > tick.availableB) {
                    amountBSold = tick.availableB;
                }
                // Underpays actual price if self, otherwise overpay (to not mess rounding)
                uint256 assetAPayment = assetBInAssetA(amountBSold, vars.currentPrice, !_self);

                tick.availableB -= amountBSold;
                tick.assetBToA.sold += amountBSold;
                tick.assetBToA.bought += assetAPayment;

                vars.offerAInB -= amountBSold;
                vars.protocolSoldB += amountBSold;
                vars.protocolBoughtA += assetAPayment;
            }

            // If there is still available A, use the offer with B to buy it
            if (vars.offerBInA > 0 && tick.availableA > 0) {
                // Buying Asset A using Asset B
                uint256 amountASold = vars.offerBInA;
                if (vars.offerBInA > tick.availableA) {
                    amountASold = tick.availableA;
                }
                // Underpays actual price if self, otherwise overpay (to not mess rounding)
                uint256 assetBPayment = assetAInAssetB(amountASold, vars.currentPrice, !_self);

                tick.availableA -= amountASold;
                tick.assetAToB.sold += amountASold;
                tick.assetAToB.bought += assetBPayment;

                vars.offerBInA -= amountASold;
                vars.protocolSoldA += amountASold;
                vars.protocolBoughtB += assetBPayment;
            }

            // If no more available, increase tick to the next. Can be expensive if no-thing happend for a long time
            if (tick.availableA == 0 && vars.oldestTickAvailableA == i) {
                vars.oldestTickAvailableA = i + 1;
            }
            if (tick.availableB == 0 && vars.oldestTickAvailableB == i) {
                vars.oldestTickAvailableB = i + 1;
            }

            // Update the storage
            ticks[i] = tick;
        }

        if (vars.oldestTickAvailableA > oldestTickA) {
            oldestTickAvailableA = _toU32(vars.oldestTickAvailableA);
        }
        if (vars.oldestTickAvailableB > oldestTickB) {
            lastTickAvailableB = _toU32(vars.oldestTickAvailableB);
        }

        int256 flowA = int256(vars.protocolBoughtA) - int256(vars.protocolSoldA);
        int256 flowB = int256(vars.protocolBoughtB) - int256(vars.protocolSoldB);

        return (flowA, flowB);
    }

    function _lastUsedTick(uint256 _lastTickA, uint256 _lastTickB) internal pure returns (uint256) {
        uint256 start;
        if (_lastTickA == 0 && _lastTickB == 0) {
            revert("No deposits");
        } else if (_lastTickA * _lastTickB == 0) {
            // one are zero (the both case is handled explicitly above)
            start = _lastTickA > _lastTickB ? _lastTickA : _lastTickB;
        } else {
            start = _lastTickA < _lastTickB ? _lastTickA : _lastTickB;
        }
        return start;
    }

    function _toU128(uint256 _a) internal pure returns (uint128) {
        if (_a > type(uint128).max) {
            revert("Overflow");
        }
        return uint128(_a);
    }

    function _toU240(uint256 _a) internal pure returns (uint240) {
        if (_a > type(uint240).max) {
            revert("Overflow");
        }
        return uint240(_a);
    }

    function _toU32(uint256 _a) internal pure returns (uint32) {
        if (_a > type(uint32).max) {
            revert("Overflow");
        }
        return uint32(_a);
    }
}
