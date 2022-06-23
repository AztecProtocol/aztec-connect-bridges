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

contract DCABridge is BridgeBase, Test {
    using SafeERC20 for IERC20;

    struct DCA {
        uint256 amount;
        uint256 slope;
        uint256 startEpoch;
        uint256 endTime;
    }

    struct Point {
        int256 bias; // just easier with int256 to not think about casting.
        int256 slope;
        uint256 ts;
        uint256 available;
        uint256 bought;
    }

    IERC20 internal constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    uint256 public constant DAY = 1 days;

    uint256 public constant ACC_PRECISION = 1e12;

    uint256 public epochLastSell = 1;
    uint256 public epoch;

    uint256 public dust;

    // epoch => point
    mapping(uint256 => Point) public history;
    // Timestamp => slope change
    mapping(uint256 => int256) public changes;
    // interactionNonce => DCA
    mapping(uint256 => DCA) public dcas;
    // timestamp => epoch
    mapping(uint256 => uint256) public tsToEpoch;

    uint256 public price = 900017768410818; // 1111 usd per eth

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        history[0].ts = block.timestamp;
    }

    function getHistory(uint256 _epoch) public view returns (Point memory) {
        return history[_epoch];
    }

    function getDCA(uint256 _nonce) public view returns (DCA memory) {
        return dcas[_nonce];
    }

    function setPrice(uint256 _price) public {
        price = _price;
    }

    function getPrice() public view returns (uint256) {
        // Price will be amount of eth per token (e.g., 0.1 -> 0.1 eth per token).
        return price;
    }

    function _swap(uint256 _input) public view returns (uint256) {
        return (_input * getPrice()) / 1e18;
    }

    function canSell() public view returns (uint256) {
        uint256 _epoch = epochLastSell;
        uint256 _max = epoch;

        uint256 sellSum = 0;
        for (uint256 i = _epoch; i <= _max; i++) {
            Point storage p = history[i];
            sellSum += p.available;
        }
        return sellSum;
    }

    function performSwap() public {
        checkPoint();

        uint256 _epoch = epochLastSell;
        uint256 _max = epoch;

        // Something in here seems to be going wrong. I am getting the first accumulator for the

        uint256 sellSum = 0;
        for (uint256 i = _epoch; i <= _max; i++) {
            Point storage p = history[i];
            sellSum += p.available;
        }

        uint256 ethBought;
        if (sellSum != 0) {
            ethBought = _swap(sellSum);

            for (uint256 i = _epoch; i <= _max; i++) {
                Point storage p = history[i];
                if (p.available != 0) {
                    uint256 ethToPoint = (ethBought * p.available) / sellSum;
                    p.bought = ethToPoint;
                    p.available = 0;
                }
            }
        }

        epochLastSell = _max;

        emit log_named_decimal_uint("sold       ", sellSum, 18);
        emit log_named_decimal_uint("bougth     ", ethBought, 18);
    }

    function deposit(
        uint256 _nonce,
        uint256 _amount,
        uint256 _endTime
    ) public {
        uint256 endTime = (_endTime / DAY) * DAY;

        if (block.timestamp >= endTime) {
            revert("Start must be before end");
        }

        checkPoint();

        uint256 slope = _amount / (endTime - block.timestamp);
        uint256 amount = slope * (endTime - block.timestamp);
        dust += (_amount - amount);

        Point memory lastPoint = history[epoch];
        epoch++;

        DCA memory dca = DCA({amount: amount, slope: slope, startEpoch: epoch, endTime: endTime});

        dcas[_nonce] = dca;

        lastPoint.bias += int256(amount);
        lastPoint.slope += int256(slope);
        lastPoint.bought = 0;
        lastPoint.available = 0;
        history[epoch] = lastPoint;

        changes[endTime] += int256(dca.slope);
    }

    function checkPoint() public {
        uint256 _epoch = epoch;

        Point memory lastPoint;
        lastPoint.ts = block.timestamp;

        if (_epoch > 0) {
            lastPoint = history[_epoch];
        }
        uint256 lastCheckpoint = lastPoint.ts;

        // If no time-difference, nothing to update (if deposit, will be updated separately)
        if (_epoch > 0 && lastCheckpoint == block.timestamp) {
            return;
        }

        uint256 t_i = (lastCheckpoint / DAY) * DAY;

        // Compute points for next tick until we reach time = now
        for (uint256 i = 0; i < 255; i++) {
            bool crossed;
            t_i += DAY;

            // If next tick is in future, set time to now, otherwise mark that tick was crossed.
            if (t_i > block.timestamp) {
                t_i = block.timestamp;
            } else {
                crossed = true;
            }

            // Compute tha mount to sell (can at most be bias).
            int256 toSell = lastPoint.slope * int256(t_i - lastCheckpoint);
            if (toSell > lastPoint.bias) {
                toSell = lastPoint.bias;
            }

            // Apply changes since prev point.
            lastPoint.bias -= toSell;
            lastPoint.available = uint256(toSell);
            lastPoint.ts = lastCheckpoint = t_i;

            // Add the point to the history
            _epoch++;
            history[_epoch] = lastPoint;

            // If we have crossed a tick check add the epoch to time mapping
            // If any DCA ends here apply changes and add another point.
            if (crossed) {
                tsToEpoch[t_i] = _epoch;
                int256 change = changes[t_i];
                if (change == 0) {
                    // If no changes, unnecessary to add an extra point to history
                    continue;
                }

                lastPoint.slope -= change;
                if (lastPoint.slope < 0) {
                    lastPoint.slope = 0;
                }
                lastPoint.available = 0;
                _epoch++;
                history[_epoch] = lastPoint;
            }

            // We have hit that time = now, so just break early
            if (t_i == block.timestamp) {
                break;
            }
        }

        epoch = _epoch;
    }

    function ethAccumulated(uint256 _nonce) public view returns (uint256) {
        DCA storage dca = dcas[_nonce];
        if (dca.endTime > block.timestamp) {
            revert("Still accumulating");
        }
        uint256 endEpoch = tsToEpoch[dca.endTime];

        uint256 myEth;
        Point storage lastPoint = history[dca.startEpoch];
        for (uint256 i = dca.startEpoch + 1; i <= endEpoch; i++) {
            Point storage p = history[i];
            myEth += uint256(int256(p.bought * dca.slope) / p.slope);
            lastPoint = p;
        }
        return myEth;
    }

    function finalise(uint256 _nonce) external {
        checkPoint();
        _nonce;
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
