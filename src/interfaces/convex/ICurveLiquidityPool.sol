// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

interface ICurveLiquidityPool {
    function add_liquidity(uint256[2] memory _amounts, uint256 _min_mint_amount) external payable returns (uint256);

    function add_liquidity(uint256[3] memory _amounts, uint256 _min_mint_amount) external;
}
