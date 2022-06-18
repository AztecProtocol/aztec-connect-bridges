// SPDX-License-Identifier: GPLv2
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ILido is IERC20 {
    function getTotalShares() external view returns(uint256);

    function sharesOf(address _account) external view returns (uint256);

    function getSharesByPooledEth(uint256 _amount) external view returns (uint256);

    function getPooledEthByShares(uint256 _amount) external view returns (uint256);

    function submit(address _referral) external payable returns (uint256);
}
