// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../../lib/ds-test/src/test.sol";

import {WadRayMath} from "./../../bridges/aave/libraries/WadRayMath.sol";

contract RoundingTest is DSTest {
    using WadRayMath for uint256;

    // function testRounding(uint128 amountIn, uint128 indexAdd) public {
    //     uint256 amount = amountIn; // using uint128 to not run into overflow
    //     uint256 index = 1e27 + indexAdd;

    //     uint256 intermediateVal = amount.rayMul(index);
    //     uint256 output = intermediateVal.rayDiv(index);

    //     assertEq(
    //         amount,
    //         output,
    //         "Scaled amounts don't match due to rounding issues"
    //     );
    // }
}
