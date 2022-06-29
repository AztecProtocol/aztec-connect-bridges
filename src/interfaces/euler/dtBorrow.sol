pragma solidity >=0.8.4;

interface dBorrow {

    function borrow(uint subAccountId, uint amount) external;
    function repay(uint subAccountId, uint amount) external;

    
    

}
