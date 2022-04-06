// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {Vm} from './../../Vm.sol';
import {DSTestPlus} from '../../../../lib/solmate/src/test/utils/DSTestPlus.sol';

contract TestHelper is DSTestPlus {
    Vm internal constant VM = Vm(HEVM_ADDRESS);

    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a > b ? a : b;
    }

    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    function _setTokenBalance(
        address token,
        address user,
        uint256 balance
    ) internal {
        uint256 slot = 2;
        if (token == address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48)) {
            slot = 9;
        } else if (token == address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599)) {
            slot = 0;
        } else if (token == address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2)) {
            slot = 3;
        }

        VM.store(token, keccak256(abi.encode(user, slot)), bytes32(uint256(balance)));

        assertEq(IERC20(token).balanceOf(user), balance, 'wrong balance');
    }

    function assertNotEq(address a, address b) internal {
        if (a == b) {
            emit log('Error: a != b not satisfied [address]');
            emit log_named_address('  Expected', b);
            emit log_named_address('    Actual', a);
            fail();
        }
    }

    function assertFalse(bool condition, string memory err) internal {
        if (condition) {
            emit log_named_string('Error', err);
            fail();
        }
    }

    function assertCloseTo(
        uint256 a,
        uint256 b,
        uint256 c
    ) internal {
        uint256 diff = a > b ? a - b : b - a;
        if (diff > c) {
            emit log('Error: a close to b not satisfied [uint256]');
            emit log_named_uint(' Expected', b);
            emit log_named_uint('   Actual', a);
            fail();
        }
    }
}
