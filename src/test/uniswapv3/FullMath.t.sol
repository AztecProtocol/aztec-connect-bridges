pragma solidity 0.8.10;

import "../../../lib/ds-test/src/test.sol";
import {Vm} from "../../../lib/forge-std/src/Vm.sol";
import {FullMath} from '../../bridges/uniswapv3/libraries/FullMath.sol';

import { console } from '../console.sol';

contract MathTest is DSTest {

    Vm private vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    uint256 constant Q128 = 2 ** 128;
    uint256 constant MAX_UINT = type(uint256).max;

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
        uint256 denominator = 1099511726541;
        uint256 actual = FullMath.mulDiv(2 ** 255, 2 ** 32, denominator);
        assertEq(actual, expected);
    }

    function testShouldCorrectlyCalculateMulDivWithOverflow3() public {
        uint256 expected = 226156403985286027850009587026819599863747406243487534755484927924122279478;
        uint256 denominator = 1099511726500;
        uint256 actual = FullMath.mulDiv(2 ** 255, 2 ** 32, denominator);
        assertEq(actual, expected);
    }

    function testShouldCorrectlyCalculateMulDivWithOverflow4() public {
        uint256 expected = 9706320845840781459127142684712331703450251785421600893256042878826505;
        uint256 denominator = 7519878498690977247166484629857052324372;
        uint256 actual = FullMath.mulDiv(74546461817018951432445240571000390099089545977406, 979125657354410079800799730287044976961723621754204857696697, denominator);
        assertEq(actual, expected);
    }

    // some tests taken from uniswap FullMath tests
    function testMulDivShouldRevertOnDivideByZero() public {
        vm.expectRevert(bytes(''));
        FullMath.mulDiv(10, 5, 0);
    }

    function testMulDivShouldRevertOnDivideByZeroAndNumeratorOverflows() public {
        vm.expectRevert(bytes(''));
        FullMath.mulDiv(Q128, Q128, 0);
    }

    function testMulDivShouldRevertIfOutputOverflowsUint256() public {
        vm.expectRevert(bytes(''));
        FullMath.mulDiv(Q128, Q128, 1);
    }

    function testMulDivShouldRevertOnOverflowWithAllMaxInputs() public {
        vm.expectRevert(bytes(''));
        FullMath.mulDiv(MAX_UINT, MAX_UINT, MAX_UINT - 1);
    }

    function testMulDivCorrectlyCalculatesAllMaxInputs() public {
        uint256 expected = MAX_UINT;
        uint256 actual = FullMath.mulDiv(MAX_UINT, MAX_UINT, MAX_UINT);
        assertEq(actual, expected);
    }

    function testMulDivAccurateWithoutPhantomOverflow() public {
        uint256 expected = Q128 / 3;
        uint256 actual = FullMath.mulDiv(Q128, (50 * Q128) / 100, (150 * Q128) / 100);
        assertEq(actual, expected);
    }

    function testMulDivAccurateWithPhantomOverflow() public {
        uint256 expected = (4375 * Q128) / 1000;
        uint256 actual = FullMath.mulDiv(Q128, 35 * Q128, 8 * Q128);
        assertEq(actual, expected);
    }

    function testMulDivAccurateWithPhantomOverflowAndRepeatingDecimal() public {
        uint256 expected = Q128 / 3;
        uint256 actual = FullMath.mulDiv(Q128, 1000 * Q128, 3000 * Q128);
        assertEq(actual, expected);
    }

    function testMulDivRoundingUpShouldRevertOnDivideByZero() public {
        vm.expectRevert(bytes(''));
        FullMath.mulDivRoundingUp(Q128, 5, 0);
    }

    function testMulDivRoundingUpShouldRevertOnDivideByZeroAndNumeratorOverflows() public {
        vm.expectRevert(bytes(''));
        FullMath.mulDivRoundingUp(Q128, Q128, 0);
    }

    function testMulDivRoundingUpShouldRevertIfOutputOverflowsUint256() public {
        vm.expectRevert(bytes(''));
        FullMath.mulDivRoundingUp(Q128, Q128, 1);
    }

    function testMulDivRoundingUpShouldRevertOnOverflowWithAllMaxInputs() public {
        vm.expectRevert(bytes(''));
        FullMath.mulDivRoundingUp(MAX_UINT, MAX_UINT, MAX_UINT - 1);
    }

    function testMulDivRoundingUpRevertsIfOverflowsUint256AfterRounding() public {
        vm.expectRevert(bytes(''));
        FullMath.mulDivRoundingUp(535006138814359, 432862656469423142931042426214547535783388063929571229938474969, 2);
    }

    function testMulDivRoundingUpRevertsIfOverflowsUint256AfterRounding2() public {
        vm.expectRevert(bytes(''));
        FullMath.mulDivRoundingUp(115792089237316195423570985008687907853269984659341747863450311749907997002549, 115792089237316195423570985008687907853269984659341747863450311749907997002550, 115792089237316195423570985008687907853269984653042931687443039491902864365164);
    }

    function testMulDivRoundingUpCorrectlyCalculatesAllMaxInputs() public {
        uint256 expected = MAX_UINT;
        uint256 actual = FullMath.mulDivRoundingUp(MAX_UINT, MAX_UINT, MAX_UINT);
        assertEq(actual, expected);
    }

    function testMulDivRoundingUpAccurateWithoutPhantomOverflow() public {
        uint256 expected = (Q128 / 3) + 1;
        uint256 actual = FullMath.mulDivRoundingUp(Q128, (50 * Q128) / 100, (150 * Q128) / 100);
        assertEq(actual, expected);
    }

    function testMulDivRoundingUpAccurateWithPhantomOverflow() public {
        uint256 expected = (4375 * Q128) / 1000;
        uint256 actual = FullMath.mulDivRoundingUp(Q128, 35 * Q128, 8 * Q128);
        assertEq(actual, expected);
    }

    function testMulDivRoundingUpAccurateWithPhantomOverflowAndRepeatingDecimal() public {
        uint256 expected = (Q128 / 3) + 1;
        uint256 actual = FullMath.mulDivRoundingUp(Q128, 1000 * Q128, 3000 * Q128);
        assertEq(actual, expected);
    }

    function testShouldCorrectlyCalculateMulDivRoundingUpWithOverflow() public {
        uint256 expected = 9706320845840781459127142684712331703450251785421600893256042878826505 + 1;
        uint256 denominator = 7519878498690977247166484629857052324372;
        uint256 actual = FullMath.mulDivRoundingUp(74546461817018951432445240571000390099089545977406, 979125657354410079800799730287044976961723621754204857696697, denominator);
        assertEq(actual, expected);
    }

    function testShouldCorrectlyCalculateMulDivRoundingUpWithOverflow2() public {
        uint256 expected = 226156403976852818508471049503229747518837086045759001909431540172203025029 + 1;
        uint256 denominator = 1099511726541;
        uint256 actual = FullMath.mulDivRoundingUp(2 ** 255, 2 ** 32, denominator);
        assertEq(actual, expected);
    }

    function testShouldCorrectlyCalculateMulDivRoundingUpWithOverflow3() public {
        uint256 expected = 226156403985286027850009587026819599863747406243487534755484927924122279479;
        uint256 denominator = 1099511726500;
        uint256 actual = FullMath.mulDivRoundingUp(2 ** 255, 2 ** 32, denominator);
        assertEq(actual, expected);
    }
}