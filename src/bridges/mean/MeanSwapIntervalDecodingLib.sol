// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {ErrorLib} from "../base/ErrorLib.sol";

library MeanSwapIntervalDecodingLib {

    function calculateSwapInterval(uint8 _swapIntervalCode) internal pure returns (uint32) {
        if (_swapIntervalCode == 0) {
            return 1 weeks;
        } else if (_swapIntervalCode == 1) {
            return 1 days;
        } else if (_swapIntervalCode == 2) {
            return 4 hours;
        } else if (_swapIntervalCode == 3) {
            return 1 hours;
        } else if (_swapIntervalCode == 4) {
            return 30 minutes;
        } else if (_swapIntervalCode == 5) {
            return 15 minutes;
        } else if (_swapIntervalCode == 6) {
            return 5 minutes;
        } else if (_swapIntervalCode == 7) {
            return 1 minutes;
        } else {
            revert ErrorLib.InvalidAuxData();
        }
    }
}
