// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";

contract TestHelper is Test {
    function assertNotEq(address a, address b) internal {
        if (a == b) {
            emit log("Error: a != b not satisfied [address]");
            emit log_named_address("  Expected", b);
            emit log_named_address("    Actual", a);
            fail();
        }
    }
}
