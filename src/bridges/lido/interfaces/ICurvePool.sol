// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

interface ICurvePool {
    function coins(uint256) external view returns (address);

    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);

    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external payable returns (uint256);
}
