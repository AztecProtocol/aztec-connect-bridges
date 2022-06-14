pragma solidity >=0.8.4;

interface IWeth {
    function balanceOf(address) external view returns (uint256);

    function deposit() external payable;

    function withdraw(uint256 wad) external;

    function transfer(address dst, uint256 wad) external returns (bool);
}
