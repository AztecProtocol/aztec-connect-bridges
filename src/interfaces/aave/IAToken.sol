// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IAaveIncentivesController} from "./IAaveIncentivesController.sol";
import {IScaledBalanceToken} from "./IScaledBalanceToken.sol";

interface IAToken is IERC20Metadata, IScaledBalanceToken {
    function getIncentivesController() external view returns (IAaveIncentivesController);
}
