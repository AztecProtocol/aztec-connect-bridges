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
        // TODO: Not implemented
        // If we had an available unmatched we might do the first two in the same :thinking:
        _rebalanceAndfill(0, 0, getPrice());
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

    function getPrice() public view virtual override(BiDCABridge) returns (uint256) {
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
