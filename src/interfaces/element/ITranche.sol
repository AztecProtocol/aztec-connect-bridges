// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.6.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/draft-IERC20Permit.sol";

interface ITranche is IERC20, IERC20Permit {
    function deposit(uint256 _shares, address destination) external returns (uint256, uint256);

    function prefundedDeposit(address _destination) external returns (uint256, uint256);

    function withdrawPrincipal(uint256 _amount, address _destination) external returns (uint256);

    function withdrawInterest(uint256 _amount, address _destination) external returns (uint256);

    function interestSupply() external view returns (uint128);

    function position() external view returns (IERC20);

    function underlying() external view returns (IERC20);

    function speedbump() external view returns (uint256);

    function unlockTimestamp() external view returns (uint256);

    function hitSpeedbump() external;
}
