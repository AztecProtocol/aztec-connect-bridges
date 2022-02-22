// SPDX-License-Identifier: MIT
pragma solidity >=0.6.10 <=0.8.10;

interface IJBToken {
    function totalSupply(uint256 _projectId) external view returns (uint256);

    function balanceOf(uint256 _projectId, address _account) external view returns (uint256);

    function mint(
        uint256 _projectId,
        address _account,
        uint256 _amount
    ) external;

    function burn(
        uint256 _projectId,
        address _account,
        uint256 _amount
    ) external;

    function transferOwnership(address newOwner) external;
}
