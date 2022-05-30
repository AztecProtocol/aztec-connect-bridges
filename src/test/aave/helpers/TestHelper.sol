// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

/**
 * @notice Helper contract extending the DSTest contract with functions from Solmate and a few extra helper
 */

 import "forge-std/Test.sol";


contract TestHelper is Test{

    function assertNotEq(address a, address b) internal {
        if (a == b) {
            emit log('Error: a != b not satisfied [address]');
            emit log_named_address('  Expected', b);
            emit log_named_address('    Actual', a);
            fail();
        }
    }

/*    function assertFalse(bool condition, string memory err) internal {
        if (condition) {
            emit log_named_string('Error', err);
            fail();
        }
    }

    function assertApproxEq(
        uint256 a,
        uint256 b,
        uint256 maxDelta
    ) internal virtual {
        uint256 delta = a > b ? a - b : b - a;

        if (delta > maxDelta) {
            emit log('Error: a ~= b not satisfied [uint]');
            emit log_named_uint('  Expected', b);
            emit log_named_uint('    Actual', a);
            emit log_named_uint(' Max Delta', maxDelta);
            emit log_named_uint('     Delta', delta);
            fail();
        }
    }

    function bound(
        uint256 x,
        uint256 min,
        uint256 max
    ) internal returns (uint256 result) {
        require(max >= min, 'MAX_LESS_THAN_MIN');

        uint256 size = max - min;

        if (max != type(uint256).max) size++; // Make the max inclusive.
        if (size == 0) return min; // Using max would be equivalent as well.
        // Ensure max is inclusive in cases where x != 0 and max is at uint max.
        if (max == type(uint256).max && x != 0) x--; // Accounted for later.

        if (x < min) x += size * (((min - x) / size) + 1);
        result = min + ((x - min) % size);

        // Account for decrementing x to make max inclusive.
        if (max == type(uint256).max && x != 0) result++;

        emit log_named_uint('Bound Result', result);
    }*/
}
