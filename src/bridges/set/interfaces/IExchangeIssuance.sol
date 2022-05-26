// SPDX-License-Identifier: GPL-2.0-only
pragma solidity >=0.8.0 <=0.8.10;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {ISetToken} from './ISetToken.sol';

interface IExchangeIssuance {
    // Issues an exact amount of SetTokens using a given amount of ether.
    function issueExactSetFromETH(ISetToken _setToken, uint256 _amountSetToken) external payable returns (uint256);

    // Issues an exact amount of SetTokens for a given amount of input ERC-20 tokens.
    function issueExactSetFromToken(
        ISetToken _setToken,
        IERC20 _inputToken,
        uint256 _amountSetToken,
        uint256 _maxAmountInputToken
    ) external returns (uint256);

    // Issues SetTokens for an exact amount of input ERC-20 tokens.
    // The ERC-20 token must be approved by the sender to this contract.
    function issueSetForExactToken(
        ISetToken _setToken,
        IERC20 _inputToken,
        uint256 _amountInput,
        uint256 _minSetReceive
    ) external returns (uint256);

    // Issues SetTokens for an exact amount of input ether.
    function issueSetForExactETH(ISetToken _setToken, uint256 _minSetReceive) external payable returns (uint256);

    // Redeems an exact amount of SetTokens for an ERC-20 token.
    // The SetToken must be approved by the sender to this contract.
    function redeemExactSetForToken(
        ISetToken _setToken,
        IERC20 _outputToken,
        uint256 _amountSetToken,
        uint256 _minOutputReceive
    ) external returns (uint256);

    // Redeems an exact amount of SetTokens for ETH.
    // The SetToken must be approved by the sender to this contract.
    function redeemExactSetForETH(
        ISetToken _setToken,
        uint256 _amountSetToken,
        uint256 _minEthOut
    ) external returns (uint256);
}
