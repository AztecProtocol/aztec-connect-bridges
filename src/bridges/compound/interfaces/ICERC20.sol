pragma solidity >=0.8.0 <=0.8.10;

interface ICERC20 {
    function accrueInterest() external;

    function approve(address, uint256) external returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function balanceOfUnderlying(address) external view returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function transfer(address, uint256) external returns (uint256);

    function mint(uint256) external returns (uint256);

    function redeem(uint256) external returns (uint256);

    function redeemUnderlying(uint256) external returns (uint256);

    function underlying() external returns (address);
}