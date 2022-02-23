// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import '../../../lib/ds-test/src/test.sol';

import {WadRayMath} from './../../bridges/aave/imports/libraries/WadRayMath.sol';

contract AaveRoundingTest is DSTest {
    using WadRayMath for uint256;

    function testRounding(uint128 amountIn, uint104 indexAdd) public {
        uint256 amount = amountIn;
        uint256 index = uint256(1e27) + indexAdd;

        uint256 intermediateVal = amount.rayMul(index);
        uint256 output = intermediateVal.rayDiv(index);

        assertEq(amount, output, "Scaled amounts don't match due to rounding issues");
    }
}
