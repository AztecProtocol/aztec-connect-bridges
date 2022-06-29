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

import {BiDCABridge} from "./BiDCABridge.sol";

interface IChainlinkOracle {
    function latestRoundData()
        external
        view
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        );
}

contract UniswapDCABridge is BiDCABridge {
    using SafeERC20 for IERC20;
    bool public constant IS_TESTING = true;

    uint256 public constant MAX_AGE = 1 days; // Heartbeat of oracle is 24 hours.

    IChainlinkOracle public immutable ORACLE;

    constructor(
        address _rollupProcessor,
        address _assetA,
        address _assetB,
        uint256 _tickSize,
        address _oracle
    ) BiDCABridge(_rollupProcessor, _assetA, _assetB, _tickSize) {
        ORACLE = IChainlinkOracle(_oracle);
    }

    function rebalanceAndFillUniswap() public returns (int256, int256) {
        // Gaswise not ideal. But somewhat understandable.
        // TODO: Not implemented
        // If we had an available unmatched we might do the first two in the same :thinking:
        _rebalanceAndfill(0, 0, getPrice(), true);
        (uint256 a, uint256 b) = getAvailable();

        // We then pretty much need to loop through and match them. Almost like the rebalance. But with the caveat, that we need to also limit it based on how much we actually have available. We cannot just pull afterwards. e.g., sell == bought.

        if (a > 0 && b > 0) {
            // Note that the `protocolBoughtA` and `protocolSoldA` may not align perfectly. This is due to rounding. For a price < 1e18, the `protocolBoughtA` value will have trailing zeros due to *1e18/price computation.
            // `protocolBoughtA` is bounded by the `_offerA` value and `protocolSoldA` is bounded by `tick.availableA` at every tick, e.g., the summed availablility.

            // Note that the `protocolBoughtB` and `protocolSoldB` may not align perfectly. This is again due to rounding. For a price < 1e18, the `protocolBoughtA` value will have trailing zeros due to *1e18/price computation.
            // `protocolBoughtB` is bounded by the `_offerB` value and `protocolSoldB` is bounded by `tick.availableB` at every tick, e.g., the summed availablility.

            // Note, there is also rounding on the payment, as any trader will have the buyer overpay due to rounding up.

            _rebalanceAndfill(a, b, getPrice(), true);
        }

        (a, b) = getAvailable();

        if (a > 0) {
            // Uniswap all A to B. Then compute the price, and use price-1 as the actual price. We want to undervalue a to ensure that we cover.
        }

        if (b > 0) {
            // Uniswap all B to A. Then compute the price, and use price-1 as the actual price. We want to undervalue a to ensure that we cover.
        }

        // Find the amount Available. Then we need to get those funds. And then we can match funds.
        // Compute how much we would need to match these.
        // Flash swap these assets from uniswap
        // run rebalance again with the values, and we need to compute the price we got from uniswap.
        // Practically, we want to borrow both assets from uniswap, and then return them both. Its a bit ugly, but might be doable

        // Actually, at this point in time, say that we got 100 A and 200B (at price 1:1) that have not been matched, because they are not in the same ticks.
        // We could then run `_rebalanceAndFill(100A, 100B, getPrice())`.
        // This should give us back 100A and 100B, but have handled such that the available is now just 100B
        // with this, we could then take the funds 100B and go to uniswap. At uniswap we just swap it to A
        // From the amount of A, we can then compute the price, and we would then just use that price.
        // Annoying because we will be doing many writes and might loop over something twice or trice even
        // We could go to uniswap before handling with just internal stuff.
        // The nice thing with handling with internal first, is that it is just one thing trading on uniswap, so less rekt by slippage.

        // Make a test where we are just calling rebalance fill, with the values that are available, and see what we get. Would expect that we are not getting much out actually, so might be the best thing to do.

        return (0, 0);
    }

    function rebalanceTest(
        uint256 _a,
        uint256 _b,
        uint256 _price,
        bool _self
    ) public returns (int256, int256) {
        (int256 flowA, int256 flowB) = _rebalanceAndfill(_a, _b, _price, _self);
        if (!_self) {
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
        }
        return (flowA, flowB);
    }

    function getPrice() public virtual override(BiDCABridge) returns (uint256) {
        (, int256 answer, , uint256 updatedAt, ) = ORACLE.latestRoundData();
        if (!IS_TESTING && updatedAt + MAX_AGE < block.timestamp) {
            revert("Too old");
        }

        if (answer < 0) {
            revert("Negative price");
        }

        return uint256(answer);
    }
}
