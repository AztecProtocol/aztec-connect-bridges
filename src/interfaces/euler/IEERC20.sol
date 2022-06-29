pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IEERC20 is IERC20 {

    //First uint = subAccountID (0 for primary, 1-255 for a sub-account), Second uint = amount

    function deposit(uint, uint) external;
    function withdraw(uint, uint) external;
    function enterMarket(uint, address) external; //address here = collateral
    function borrow(uint, uint) external;
    function repay(uint, uint) external;

    
    
    
    
    
    


}
