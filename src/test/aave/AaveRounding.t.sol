// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";

import {WadRayMath} from "../../libraries/aave/WadRayMath.sol";

contract AaveRoundingTest is Test {
    using WadRayMath for uint256;

    function testRoundingMulDiv(uint128 amountIn, uint104 indexAdd) public {
        uint256 amount = amountIn;
        uint256 index = uint256(1e27) + indexAdd;

        uint256 intermediateVal = amount.rayMul(index);
        uint256 output = intermediateVal.rayDiv(index);

        assertEq(amount, output, "Scaled amounts don't match due to rounding issues");
    }

    function testFailRoundingDivMul() public {
        uint256 amount = 70124217620;
        uint256 index = uint256(1e27) + 7684960890848208697334640374;

        uint256 intermediateVal = amount.rayDiv(index);
        uint256 output = intermediateVal.rayMul(index);

        assertGe(output, amount, "Same tx deposit and withdraw will lose funds");
    }
}
