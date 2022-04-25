pragma solidity 0.8.10;

import "../../../lib/ds-test/src/test.sol";
import {Vm} from "../../../lib/forge-std/src/Vm.sol";
import {FullMath} from '../../bridges/uniswapv3/libraries/FullMath.sol';

import { console } from '../console.sol';

contract MathTest is DSTest {

    Vm private vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    function setUp() public {
    }

    function testShouldCorrectlyCalculateMulDiv() public {
        uint256 result = FullMath.mulDiv(10, 5, 2);
        assertEq(result, 25);
    }

    function testShouldCorrectlyCalculateMulDivWithIntegralDivision() public {
        uint256 result = FullMath.mulDiv(10, 5, 3);
        assertEq(result, 16);
    }

    function testShouldCorrectlyCalculateMulDivWithNoOverflow(uint64 a, uint64 b, uint256 denominator) public {
        if (denominator == 0) {
            vm.expectRevert(bytes(''));
            FullMath.mulDiv(a, b, denominator);
            return;
        }
        uint256 fullMathResult = FullMath.mulDiv(a, b, denominator);
        uint256 result = (uint256(a) * uint256(b)) / denominator;
        assertEq(fullMathResult, result);
    }

    function testShouldCorrectlyCalculateMulDivWithOverflow() public {
        uint256 expected = 2 ** 247;
        uint256 actual = FullMath.mulDiv(2 ** 255, 2 ** 32, 2 ** 40);
        assertEq(actual, expected);
    }

    function testShouldCorrectlyCalculateMulDivWithOverflow2() public {
        uint256 expected = 226156403976852818508471049503229747518837086045759001909431540172203025029;
        uint256 denominator = (2 ** 40) + 98765;
        uint256 actual = FullMath.mulDiv(2 ** 255, 2 ** 32, denominator);
        assertEq(actual, expected);
    }

    function testFullMathShouldRevertOnDivideByZero() public {
        vm.expectRevert(bytes(''));
        FullMath.mulDiv(10, 5, 0);
    }

}