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

contract SimplerDCABridge is BridgeBase, Test {
    struct DCA {
        uint256 total;
        uint256 start;
        uint256 end;
    }

    struct Tick {
        uint240 available;
        uint16 poke;
        uint256 sold;
        uint256 bought;
    }

    uint256 public constant TICK_SIZE = 1 days;

    uint256 public lastTickBought;

    // day => Tick
    mapping(uint256 => Tick) public ticks;
    // nonce => DCA
    mapping(uint256 => DCA) public dcas;

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    function pokeNextTicks(uint256 _ticks) public {
        uint256 nextTick = ((block.timestamp + TICK_SIZE - 1) / TICK_SIZE);
        pokeTicks(nextTick, _ticks);
    }

    function pokeTicks(uint256 _startTick, uint256 _ticks) public {
        for (uint256 i = _startTick; i < _startTick + _ticks; i++) {
            unchecked {
                ticks[i].poke++;
            }
        }
    }

    function deposit(
        uint256 _nonce,
        uint256 _amount,
        uint256 _ticks
    ) public {
        uint256 nextTick = ((block.timestamp + TICK_SIZE - 1) / TICK_SIZE);

        uint240 tickAmount = uint240(_amount / _ticks);

        for (uint256 i = nextTick; i < nextTick + _ticks; i++) {
            ticks[i].available += tickAmount;
        }

        dcas[_nonce] = DCA({total: _amount, start: nextTick, end: nextTick + _ticks});
    }

    function getPrice() public view returns (uint256) {
        return 900017768410818; // 1111 usd per eth
    }

    function available() public returns (uint256) {
        uint256 available = 0;
        uint256 lastTick = block.timestamp / TICK_SIZE;

        for (uint256 i = lastTickBought; i <= lastTick; i++) {
            available += ticks[i].available;
        }

        return available;
    }

    function trade(uint256 _maxEthInput) public returns (uint256, uint256) {
        uint256 price = getPrice();
        uint256 maxDaiToBuy = (_maxEthInput * 1e18) / price; // dai to buy from eth
        uint256 lastTick = block.timestamp / TICK_SIZE;

        uint256 bought = 0;

        for (uint256 i = lastTickBought; i <= lastTick; i++) {
            Tick storage tick = ticks[i];
            uint256 forSale = tick.forSale;
            uint256 buy = forSale;

            if (bought + forSale > maxDaiToBuy) {
                buy = maxDaiToBuy - bought;
            }

            tick.available -= buy;
            tick.sold += buy;
            tick.bought += (buy * price) / 1e18;
            bought += buy;

            if (bought == maxDaiToBuy) {
                break;
            }
        }

        return (0, 0);
    }

    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256,
            bool
        )
    {}
}
