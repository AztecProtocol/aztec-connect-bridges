// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface ICurveExchange {
    // solhint-disable func-name-mixedcase

    function get_best_rate(
        address _from,
        address _to,
        uint256 _amount
    ) external view returns (address, uint256);

    function get_exchange_amount(
        address _pool,
        address _from,
        address _to,
        uint256 _amount
    ) external view returns (uint256);

    function exchange(
        address _pool,
        address _from,
        address _to,
        uint256 _amount,
        uint256 _expected
    ) external payable returns (uint256);

    function exchange_with_best_rate(
        address _from,
        address _to,
        uint256 amount,
        uint256 _expected
    ) external payable returns (uint256);

    // solhint-enable func-name-mixedcase
}
