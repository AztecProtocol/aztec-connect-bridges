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
    error InvalidInput();
    
    module public immutable MODULE = module(address IEulerMarkets);  //fill in address
    IEERC20 public immutable eToken = IEERC20(address IEulerEToken);
    
     /**
     * @notice Set the address of RollupProcessor.sol
     * @param _rollupProcessor Address of RollupProcessor.sol
     */
     
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}
    
    receive() external payable {}
    
    //Approve the deposit token, and approve the token you're going to borrow
    
    function performApprovals(address _collateral, address _borrowToken) external {
    
        if (_collateral == address(0)) revert InvalidInput();
        if (_borrowToken == address(0)) revert InvalidInput();
        IERC20(_collateral).approve(EULER_MAINNET_addr, type(uint).max);
        IERC20(_borrowToken).approve(EULER_MAINNET_addr, type(uint).max);    //need to fill in EULER_MAINNET address!
        IERC20(_collateral).safeApprove(ROLLUP_PROCESSOR, type(uint256).max);
        IERC20(_borrowToken).safeApprove(ROLLUP_PROCESSOR, type(uint256).max);
        
             
             }
             
             
             
             
     /**
     * @notice Function which deposits collateral, which allows the user to borrow
     * @dev This method can only be called from RollupProcessor.sol. If `_auxData` is 0 the mint flow is executed,
     * if 1 redeem flow.
     *
     * @param _inputAssetA - ETH/ERC20 (Mint), cToken ERC20 (Redeem)
     * @param _outputAssetA - cToken (Mint), ETH/ERC20 (Redeem)
     * @param _inputValue - the amount of ERC20 token/ETH to deposit (Mint), the amount of cToken to burn (Redeem)
     * @param _interactionNonce - interaction nonce as defined in RollupProcessor.sol
     * @param _auxData - 0 (Mint), 1 (Redeem)
     * @return outputValueA - the amount of cToken (Mint) or ETH/ERC20 (Redeem) transferred to RollupProcessor.sol
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64 _auxData,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256,
            bool
        )
    { 
       if (_auxData == 0) {
           
          
       
            
    
        
        
    
    
}

