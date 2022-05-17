// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

library Errors {
    string internal constant INVALID_CALLER = '1';
    string internal constant INPUT_ASSET_A_AND_OUTPUT_ASSET_A_IS_ETH = '2';
    string internal constant INPUT_ASSET_A_NOT_ERC20_OR_ETH = '3';
    string internal constant OUTPUT_ASSET_A_NOT_ERC20_OR_ETH = '4';
    string internal constant INPUT_ASSET_B_NOT_EMPTY = '5';
    string internal constant OUTPUT_ASSET_B_NOT_EMPTY = '6';
    string internal constant INPUT_ASSET_INVALID = '7';
    string internal constant OUTPUT_ASSET_INVALID = '8';
    string internal constant INPUT_ASSET_NOT_EQ_ZK_ATOKEN = '9';
    string internal constant INVALID_ATOKEN = '10';
    string internal constant ZK_TOKEN_ALREADY_SET = '11';
    string internal constant ZK_TOKEN_DONT_EXISTS = '12';
    string internal constant ZERO_VALUE = '13';
}
