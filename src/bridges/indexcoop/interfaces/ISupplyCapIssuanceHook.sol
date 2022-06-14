pragma solidity 0.8.10;

interface ISupplyCapIssuanceHook {
    function supplyCap() external returns (uint256);
}
