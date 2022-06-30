pragma solidity >=0.8.4;

interface IEulerDToken {

    function borrow(uint, uint) external;
    function repay(uint, uint) external;
    function balanceOf(address) external view returns (uint);

    
    

}
