pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IEERC20 is IERC20 {

    //First uint = subAccountID (0 for primary, 1-255 for a sub-account), Second uint = amount

    function deposit(uint, uint) external;
    function withdraw(uint, uint) external; 
    function balanceOfUnderlying(address) external view returns (uint); //address here = account 
    function approve(address, uint) external returns (bool); //address = spender (Euler_Mainnet)
   
    
}
