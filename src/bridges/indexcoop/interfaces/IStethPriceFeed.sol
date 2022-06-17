pragma solidity >=0.8.4;

interface IStethPriceFeed{
    function current_price() external returns (uint256, bool);
    function safe_price_value() external returns (uint256);
}
