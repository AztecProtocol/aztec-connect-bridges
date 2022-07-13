pragma solidity >=0.8.4;

interface IComptroller {
    /// @notice A list of all markets
    function allMarkets(uint256 i) external view returns (address);

    function getAllMarkets() external view returns (address[] memory);

    function markets(address market)
        external
        view
        returns (
            bool isListed,
            uint256 collateralFactorMantissa,
            bool isComped
        );
}
