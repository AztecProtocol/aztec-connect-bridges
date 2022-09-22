// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

library SafeCastLib {
    function toU128(uint256 _a) internal pure returns (uint128) {
        if (_a > type(uint128).max) {
            revert("Overflow");
        }
        return uint128(_a);
    }

    function toU120(uint256 _a) internal pure returns (uint120) {
        if (_a > type(uint120).max) {
            revert("Overflow");
        }
        return uint120(_a);
    }

    function toU32(uint256 _a) internal pure returns (uint32) {
        if (_a > type(uint32).max) {
            revert("Overflow");
        }
        return uint32(_a);
    }
}
