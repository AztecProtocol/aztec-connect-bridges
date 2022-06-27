// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";

import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract BiDCABridge is BridgeBase, Test {
    using SafeERC20 for IERC20;

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

    function pokeNextTicks(uint256 _ticks) public {
        uint256 nextTick = ((block.timestamp + TICK_SIZE - 1) / TICK_SIZE);
        pokeTicks(nextTick, _ticks);
    }

    function pokeTicks(uint256 _startTick, uint256 _ticks) public {
        for (uint256 i = _startTick; i < _startTick + _ticks; i++) {
            ticks[i].poke++;
        }
    }

    function deposit(
        uint256 _nonce,
        uint256 _amount,
        uint256 _ticks,
        bool _assetA
    ) public {
        uint256 nextTick = ((block.timestamp + TICK_SIZE - 1) / TICK_SIZE);
        if (_assetA && oldestTickAvailableA == 0) {
            // Just for the first update
            oldestTickAvailableA = nextTick;
        }
        if (!_assetA && lastTickAvailableB == 0) {
            lastTickAvailableB = nextTick;
        }
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

        // Don't need to pull funds as we are getting them directly from the rollup
    }

    function getPrice() public view returns (uint256) {
        return 0.001e18; // 900017768410818; // 1111 usd per eth
    }

    function available() public view returns (uint256 availableA, uint256 availableB) {
        uint256 start = _lastUsedTick(oldestTickAvailableA, lastTickAvailableB);
        // Loop over both to get it done properly
        uint256 lastTick = block.timestamp / TICK_SIZE;
        for (uint256 i = start; i <= lastTick; i++) {
            availableA += ticks[i].availableA;
            availableB += ticks[i].availableB;
        }
    }

    function assetAInAssetB(uint256 _amount, uint256 _priceAToB) public pure returns (uint256) {
        return (_amount * _priceAToB) / 1e18;
    }

    function assetBInAssetA(uint256 _amount, uint256 _priceAToB) public pure returns (uint256) {
        return (_amount * 1e18) / _priceAToB;
    }

    function rebalanceAndfill(uint256 _offerA, uint256 _offerB) public returns (int256, int256) {
        (int256 flowA, int256 flowB) = _rebalanceAndfill(_offerA, _offerB, getPrice());
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

    function rebalanceAndFillUniswap() public returns (int256, int256) {
        // TODO: Not implemented
        // We kinda needs to rebalance it first.
        _rebalanceAndfill(0, 0, getPrice());
        // Find the amount Available. Then we need to get those funds. And then we can match funds.
        // Compute how much we would need to match these.
        // Flash swap these assets from uniswap
        // run rebalance again with the values, and we need to compute the price we got from uniswap.
        //

        // Practically, we want to borrow both assets from uniswap, and then return them both rofl. Its a bit ugly, but might be doable
        // Call rebalance again with these values borrowed.
    }

    /**
     * @notice Rebalances and trades into unfilled ticks.
     * Will rebalance based on own assets first, before allowing the ticks to be filled by external assets
     */
    function _rebalanceAndfill(
        uint256 _offerA,
        uint256 _offerB,
        uint256 _currentPrice
    ) internal returns (int256, int256) {
        // Need to loop over the ticks
        RebalanceValues memory vars;

        uint256 oldestTickA = vars.oldestTickAvailableA = oldestTickAvailableA;
        uint256 oldestTickB = vars.oldestTickAvailableB = lastTickAvailableB;
        uint256 oldestTick = _lastUsedTick(oldestTickA, oldestTickB);

        vars.currentPrice = _currentPrice;
        uint256 lastUsedPrice = ticks[oldestTick].priceAToB;
        uint256 lastUsedPriceTs = ticks[oldestTick].priceUpdated;

        if (lastUsedPrice == 0) {
            uint256 lookBack = oldestTick;
            while (lastUsedPrice == 0) {
                lookBack--;
                lastUsedPrice = ticks[lookBack].priceAToB;
                lastUsedPriceTs = ticks[lookBack].priceUpdated;
            }
        }

        vars.offerAInB = assetAInAssetB(_offerA, vars.currentPrice);
        vars.offerBInA = assetBInAssetA(_offerB, vars.currentPrice);

        uint256 nextTick = ((block.timestamp + TICK_SIZE - 1) / TICK_SIZE);
        for (uint256 i = oldestTick; i < nextTick; i++) {
            // Load a cache
            Tick memory tick = ticks[i];

            // Rebalance the tick using available balances
            if (tick.availableA > 0 && tick.availableB > 0) {
                // If we got matching, then we can try to match these based on the prices we have stored.
                uint256 price = tick.priceAToB;
                if (price == 0) {
                    int256 slope = (int256(vars.currentPrice) - int256(lastUsedPrice)) /
                        int256(block.timestamp - lastUsedPriceTs);
                    uint256 dt = i * TICK_SIZE + TICK_SIZE / 2 - lastUsedPriceTs;
                    int256 _price = int256(lastUsedPrice) + slope * int256(dt);
                    if (_price <= 0) {
                        price = 0;
                    } else {
                        price = uint256(_price);
                    }
                }

                // To compare we need same basis
                uint256 availableAInB = assetAInAssetB(tick.availableA, price);

                // If more value in A than B, we can use all available B. Otherwise, use all available A
                if (availableAInB > tick.availableB) {
                    // We got more A than B, so fill everything in B and part of A
                    uint256 availableBInA = assetBInAssetA(tick.availableB, price);

                    // Update Asset A
                    tick.assetAToB.sold += availableBInA;
                    tick.assetAToB.bought += tick.availableB;

                    // Update Asset B
                    tick.assetBToA.bought += availableBInA;
                    tick.assetBToA.sold += tick.availableB;

                    // Update available values
                    tick.availableA -= availableBInA;
                    tick.availableB = 0;
                } else {
                    // We got more B than A, fill everything in A and part of B

                    // Update Asset B
                    tick.assetBToA.sold += availableAInB;
                    tick.assetBToA.bought += tick.availableA;

                    // Update Asset A
                    tick.assetAToB.bought += availableAInB;
                    tick.assetAToB.sold += tick.availableA;

                    // Update available values
                    tick.availableA = 0;
                    tick.availableB -= availableAInB;
                }
            }

            // If there is still available B, use the offer with A to buy it
            if (vars.offerAInB > 0 && tick.availableB > 0) {
                uint256 userBuyingB = vars.offerAInB;
                if (vars.offerAInB > tick.availableB) {
                    userBuyingB = tick.availableB;
                }
                // Because of rounding, the sum of assetAPayment should be <= total offer.
                uint256 assetAPayment = assetBInAssetA(userBuyingB, vars.currentPrice);

                tick.availableB -= userBuyingB;
                tick.assetBToA.sold += userBuyingB;
                tick.assetBToA.bought += assetAPayment;

                vars.offerAInB -= userBuyingB;
                vars.protocolSoldB += userBuyingB;
                vars.protocolBoughtA += assetAPayment;
            }

            // If there is still available A, use the offer with B to buy it
            if (vars.offerBInA > 0 && tick.availableA > 0) {
                // Buying Asset A using Asset B
                uint256 amountABought = vars.offerBInA;
                if (vars.offerBInA > tick.availableA) {
                    amountABought = tick.availableA;
                }
                uint256 assetBPayment = assetAInAssetB(amountABought, vars.currentPrice);

                tick.availableA -= amountABought;
                tick.assetAToB.sold += amountABought;
                tick.assetAToB.bought += assetBPayment;

                vars.offerBInA -= amountABought;
                vars.protocolSoldA += amountABought;
                vars.protocolBoughtB += assetBPayment;
            }

            if (tick.availableA == 0 && vars.oldestTickAvailableA == i - 1) {
                // Only if the one before us also had it. Fuck
                vars.oldestTickAvailableA = i;
            }
            if (tick.availableB == 0 && vars.oldestTickAvailableB == i - 1) {
                vars.oldestTickAvailableB = i;
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
        // TODO: A bit of validation
        bool assetA = _inputAssetA.erc20Address == address(ASSET_A);
        deposit(_interactionNonce, _inputValue, _ticks, assetA);
        return (0, 0, true);
    }

    function finalise(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _nonce,
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
        (accumulated, interactionComplete) = getAccumulated(_nonce);

        if (interactionComplete) {
            DCA memory dca = dcas[_nonce];

            if (_outputAssetA.erc20Address != (dca.assetA ? address(ASSET_B) : address(ASSET_A))) {
                revert ErrorLib.InvalidOutputA();
            }

            outputValueA = accumulated;
            delete dcas[_nonce];

            // TODO: If the asset is ether, we need to do the tranfer
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

    function getTick(uint256 _day) public view returns (Tick memory) {
        return ticks[_day];
    }

    function getDCA(uint256 _nonce) public view returns (DCA memory) {
        return dcas[_nonce];
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

    // TODO: We need a way to FORCE a trade as well. Just to make it possible to exit even if it is a worse price, just by going to uniswap etc.

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
