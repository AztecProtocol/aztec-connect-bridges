pragma solidity >=0.8.4;

interface dtBorrow {

    function borrow(uint, uint) external;
    function repay(uint, uint) external;
    function balanceOf(address) external view returns (uint);

    
    

}
