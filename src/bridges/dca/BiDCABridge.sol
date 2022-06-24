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
    struct DCA {
        uint128 total;
        uint32 start;
        uint32 end;
        bool assetA;
    }

    struct SubTick {
        uint128 sold;
        uint128 bought;
    }

    struct Tick {
        uint120 availableA;
        uint120 availableB;
        uint16 poke;
        SubTick assetA;
        SubTick assetB;
    }

    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    uint256 public constant TICK_SIZE = 1 days;

    uint256 public lastTickBought;

    // day => Tick
    mapping(uint256 => Tick) public ticks;
    // nonce => DCA
    mapping(uint256 => DCA) public dcas;

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    function getTick(uint256 _day) public view returns (Tick memory) {
        return ticks[_day];
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
        if (lastTickBought == 0) {
            // Just for the first update
            lastTickBought = nextTick;
        }
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

    function available() public view returns (uint256 availableAsset) {
        uint256 lastTick = block.timestamp / TICK_SIZE;
        for (uint256 i = lastTickBought; i <= lastTick; i++) {
            availableAsset += ticks[i].available;
        }
    }

    function trade(uint256 _maxEthInput)
        public
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint256 price = getPrice();
        uint256 maxDaiToBuy = (_maxEthInput * 1e18) / price; // max dai to buy with eth
        uint256 lastTick = block.timestamp / TICK_SIZE;
        uint256 sold = 0;
        uint256 newLastBought = lastTickBought;

        // Fill the orders chronologically.
        for (uint256 i = lastTickBought; i <= lastTick; i++) {
            Tick storage tick = ticks[i];
            uint256 available = tick.available;

            if (available == 0) {
                continue;
            }

            uint256 buy = available;

            if (sold + available > maxDaiToBuy) {
                buy = maxDaiToBuy - sold;
            }

            tick.available -= _toU240(buy);
            tick.sold += _toU128(buy);
            tick.bought += _toU128((buy * price) / 1e18);
            sold += buy;

            newLastBought = i;

            if (sold == maxDaiToBuy) {
                break;
            }
        }

        lastTickBought = newLastBought;

        uint256 bought = (sold * price) / 1e18;
        uint256 refund = _maxEthInput - bought;

        if (refund > 0) {
            // Transfer
        }
        //

        return (bought, sold, refund);
    }

    function getAccumulated(uint256 _nonce) public view returns (uint256 accumulated, bool ready) {
        DCA storage dca = dcas[_nonce];
        uint256 start = dca.start;
        uint256 end = dca.end;
        uint240 tickAmount = _toU240(dca.total / (end - start));

        for (uint256 i = start; i < end; i++) {
            Tick storage tick = ticks[i];
            if (tick.sold == 0) {
                break;
            }
            accumulated += (tick.bought * uint256(tickAmount)) / uint256(tick.sold);
            if (tick.available > 0) {
                ready = false;
                break;
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
        deposit(_interactionNonce, _inputValue, _ticks);
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
        (accumulated, interactionComplete) = getAccumulated(_nonce);

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
