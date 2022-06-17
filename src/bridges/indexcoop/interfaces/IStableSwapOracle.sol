pragma solidity 0.8.10;
pragma experimental ABIEncoderV2;

interface IStableSwapOracle{
    function stethPrice() external returns (uint256);
}
