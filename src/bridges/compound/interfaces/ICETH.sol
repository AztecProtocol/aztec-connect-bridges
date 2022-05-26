pragma solidity >=0.8.0 <=0.8.10;

interface ICETH {
    function approve(address, uint256) external returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function transfer(address, uint256) external returns (uint256);

    function mint() external payable;

    function redeem(uint256) external returns (uint256);

    function redeemUnderlying(uint256) external returns (uint256);
}
