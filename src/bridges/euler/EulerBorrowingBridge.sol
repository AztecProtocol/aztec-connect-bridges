// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";

import {ErrorLib} from "./../base/ErrorLib.sol";
import {BridgeBase} from "./../base/BridgeBase.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IEERC20} from "../../interfaces/euler/IEERC20.sol";
import {module} from "../../interfaces/euler/module.sol";

/**
 * @title Aztec Connect Bridge for the Euler protocol
 * @notice You can use this contract to deposit collateral and borrow.
 * @dev Implementation of the IDefiBridge interface for eTokens.
 */

contract EulerBorrowingBridge is BridgeBase {
    
    using SafeERC20 for IERC20;
    
    error MarketNotListed();
    
    module public immutable MODULE = module(address);  //fill in address
    
     /**
     * @notice Set the address of RollupProcessor.sol
     * @param _rollupProcessor Address of RollupProcessor.sol
     */
     
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}
    
    receive() external payable {}
    
        function performApprovals(address _eToken) external {
        (bool isListed, , ) = MODULE.markets(_eToken);
        if (!isListed) revert MarketNotListed();
        _preApprove(IEERC20(_eToken));
    }
    
    
}

