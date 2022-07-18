// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

interface IYearnVault {    
    function deposit(uint256 amount) external returns (uint256);
    
    function withdraw(uint256 maxShares) external returns (uint256);
    
    function approve(address spender, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function token() external view returns (address);
    
    function decimals() external view returns (uint256);
    
    function availableDepositLimit() external view returns (uint256);

    function pricePerShare() external view returns (uint256);
}
