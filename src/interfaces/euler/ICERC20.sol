pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ICERC20 is IERC20 {
    //first uint = subAccountId, second uint = amount 
    // subAccountId has to be 0 for primary account 
    
    function deposit(uint, uint) external;          
    function withdraw(uint, uint) external;        
    function borrow(uint, uint) external;
    
    
    
    
  
    
    
    
}
