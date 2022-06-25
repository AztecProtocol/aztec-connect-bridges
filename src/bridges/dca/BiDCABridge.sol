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
        uint256 offerAInB;
        uint256 aBought;
        uint256 bBought;
        uint256 offerBInA;
        uint256 availableA;
        uint256 availableB;
        uint256 lastTickAvailableA;
        uint256 lastTickAvailableB;
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
        SubTick assetA;
        SubTick assetB;
        uint256 priceAToB;
        uint256 priceUpdated;
    }

    IERC20 public immutable ASSET_A;
    IERC20 public immutable ASSET_B;
    uint256 public immutable TICK_SIZE;

    uint256 public lastTickAvailableA;
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
    }

    function getTick(uint256 _day) public view returns (Tick memory) {
        return ticks[_day];
    }

    function getDCA(uint256 _nonce) public view returns (DCA memory) {
        return dcas[_nonce];
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
        if (_assetA && lastTickAvailableA == 0) {
            // Just for the first update
            lastTickAvailableA = nextTick;
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
    }

    function getPrice() public view returns (uint256) {
        return 900017768410818; // 1111 usd per eth
    }

    function available() public view returns (uint256 availableA, uint256 availableB) {
        uint256 lastTickA = lastTickAvailableA;
        uint256 lastTickB = lastTickAvailableB;
        uint256 start = lastTickA < lastTickB ? lastTickA : lastTickB;

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

    function rebalanceAndfill(uint256 _offerA, uint256 _offerB) public {
        // Need to loop over the ticks
        uint256 nextTick = ((block.timestamp + TICK_SIZE - 1) / TICK_SIZE);
        uint256 lastTickA = lastTickAvailableA;
        uint256 lastTickB = lastTickAvailableB;
        uint256 _lastTick = lastTickA < lastTickB ? lastTickA : lastTickB;

        RebalanceValues memory vars;
        vars.currentPrice = getPrice();
        uint256 lastUsedPrice = ticks[_lastTick].priceAToB;
        uint256 lastUsedPriceTs = ticks[_lastTick].priceUpdated;

        if (lastUsedPrice == 0) {
            revert("FUCK");
            // We gotta look back to find the correct price
            // If we loop should be pretty small as a convert updates, and we are using from the last tick.
            // We might want to update the price of the current tick as well :thinking:
            // Find the lastest price we can find. We can then reuse that.
        }

        // Rounding down.
        vars.offerAInB = assetAInAssetB(_offerA, vars.currentPrice);
        vars.offerBInA = assetBInAssetA(_offerB, vars.currentPrice);

        for (uint256 i = _lastTick; i < nextTick; i++) {
            Tick storage tick = ticks[i];

            vars.availableA = tick.availableA;
            vars.availableB = tick.availableB;

            // Rebalance the tick using available balances
            if (vars.availableA > 0 && vars.availableB > 0) {
                // If we got matching, then we can try to match these based on the prices we have stored.
                uint256 price = tick.priceAToB;
                if (price == 0) {
                    price = lastUsedPrice;
                    // Need to know timing of the lastPrice as well.
                    // TODO: Can we have that lastUsedPriceTs. Well yes, because that one is updated in this round no? Or, no actually, because if it is updated, we have the price. Don't think it, but better check. Yes, we can hit it actually. If the current one is going on and not filled. But then we should have a price, so should not be an actual issue I think.
                    int256 slope = (int256(vars.currentPrice) - int256(lastUsedPrice)) /
                        int256(block.timestamp - lastUsedPriceTs);
                    // the ts could in practice be updated at the end of the day. But if it is, the price is also updated, and we can skip this entire thing.
                    uint256 dt = i * TICK_SIZE - lastUsedPriceTs;
                    int256 _price = int256(lastUsedPrice) + slope * int256(dt);
                    if (_price <= 0) {
                        price = 0;
                    } else {
                        price = uint256(_price);
                    }
                }

                // To compare we need same basis
                uint256 availableAInB = assetAInAssetB(vars.availableA, price);

                // If more value in A than B, we can use all available B. Otherwise, use all available A
                if (availableAInB > vars.availableB) {
                    // We got more A than B, so fill everything in B and part of A
                    uint256 availableBInA = assetBInAssetA(vars.availableB, price);

                    // Update available values
                    tick.availableA -= availableBInA;
                    tick.availableB = 0;

                    // Update Asset A
                    tick.assetA.sold += availableBInA;
                    tick.assetA.bought += vars.availableB;

                    // Update Asset B
                    tick.assetB.bought += availableBInA;
                    tick.assetB.sold += vars.availableB;
                } else {
                    // We got more B than A, fill everything in A and part of B

                    // Update available values
                    tick.availableA = 0;
                    tick.availableB -= availableAInB;

                    // Update Asset B
                    tick.assetB.sold += availableAInB;
                    tick.assetB.bought += vars.availableA;

                    // Update Asset A
                    tick.assetA.bought += availableAInB;
                    tick.assetA.sold += vars.availableA;
                }
            }

            // If there is still available B, use the offer with A to buy it
            if (vars.offerAInB > 0 && vars.availableB > 0) {
                uint256 userBuyingB = vars.offerAInB;
                if (vars.offerAInB > vars.availableB) {
                    userBuyingB = vars.availableB;
                }
                // Because of rounding, the sum of assetAPayment should be <= total offer.
                uint256 assetAPayment = assetBInAssetA(userBuyingB, vars.currentPrice);

                tick.availableB -= userBuyingB;
                tick.assetB.sold += userBuyingB;
                tick.assetB.bought += assetAPayment;

                vars.offerAInB -= userBuyingB;
                vars.bBought += userBuyingB;
            }

            // If there is still available A, use the offer with B to buy it
            if (vars.offerBInA > 0 && vars.availableA > 0) {
                // Buying Asset A using Asset B
                uint256 amountABought = vars.offerBInA;
                if (vars.offerBInA > vars.availableA) {
                    amountABought = vars.availableA;
                }
                uint256 assetBPayment = assetAInAssetB(amountABought, vars.currentPrice);

                tick.availableA -= amountABought;
                tick.assetA.sold += amountABought;
                tick.assetA.bought += assetBPayment;

                vars.offerBInA -= amountABought;
                vars.aBought += amountABought;
            }

            if (vars.availableA == 0) {
                vars.lastTickAvailableA = i;
            }
            if (vars.availableB == 0) {
                vars.lastTickAvailableB = i;
            }
        }

        if (vars.lastTickAvailableA > lastTickAvailableA) {
            lastTickAvailableA = _toU32(vars.lastTickAvailableA);
        }
        if (vars.lastTickAvailableB > lastTickAvailableB) {
            lastTickAvailableB = _toU32(vars.lastTickAvailableB);
        }

        // If there is still part of the offer left, give refunds.
        if (vars.offerAInB > 0) {
            vars.aBought += assetBInAssetA(vars.offerAInB, vars.currentPrice);
        }
        if (vars.offerBInA > 0) {
            vars.bBought += assetAInAssetB(vars.offerBInA, vars.currentPrice);
        }

        // TODO: Need to handle the token transfers out as well.

        // Handle transfers
        if (_offerA > vars.aBought) {
            // The offer is more than what we get back, pull
            ASSET_A.safeTransferFrom(msg.sender, address(this), _offerA - vars.aBought);
        }
        if (_offerA < vars.aBought) {
            // The offer is less than we get back, e.g., we bought
            ASSET_A.safeTransfer(msg.sender, vars.aBought - _offerA);
        }
        if (_offerB > vars.bBought) {
            // The offer is more than what we get back, pull
            ASSET_B.safeTransferFrom(msg.sender, address(this), _offerB - vars.bBought);
        }
        if (_offerB < vars.bBought) {
            // The offer is less than we get back, e.g., we bought
            ASSET_B.safeTransfer(msg.sender, vars.bBought - _offerB);
        }
    }

    function getAccumulated(uint256 _nonce) public returns (uint256 accumulated, bool ready) {
        DCA storage dca = dcas[_nonce];
        uint256 start = dca.start;
        uint256 end = dca.end;
        uint240 tickAmount = _toU240(dca.total / (end - start));
        bool assetA = dca.assetA;

        ready = true;

        if (assetA) {
            for (uint256 i = start; i < end; i++) {
                Tick storage tick = ticks[i];
                uint256 sold = tick.assetA.sold;
                ready = ready && tick.availableA > 0 && sold == 0;
                accumulated += sold == 0 ? 0 : (tick.assetA.bought * uint256(tickAmount)) / uint256(sold);
            }
        } else {
            for (uint256 i = start; i < end; i++) {
                Tick storage tick = ticks[i];
                uint256 sold = tick.assetB.sold;
                ready = ready && tick.availableB > 0 && sold == 0;
                accumulated += sold == 0 ? 0 : (tick.assetB.bought * uint256(tickAmount)) / uint256(sold);
            }
        }
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
        //deposit(_interactionNonce, _inputValue, _ticks);
        return (0, 0, true);
    }

    function finalise(
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
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
        // TODO: A bit of validation
        uint256 accumulated;
        // (accumulated, interactionComplete) = getAccumulated(_nonce);

        if (interactionComplete) {
            outputValueA = accumulated;
            delete dcas[_nonce];
            // Do a transfer of ether to the rollup
        }
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
