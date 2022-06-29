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
import {dtBorrow} from "../../interfaces/euler/dtBorrow.sol";

/**
 * @title Aztec Connect Bridge for the Euler protocol
 * @notice You can use this contract to deposit collateral and borrow.
 * @dev Implementation of the IDefiBridge interface for eTokens.
 */

contract EulerBorrowingBridge is BridgeBase {
    
    using SafeERC20 for IERC20;
    
    error MarketNotListed();
    error InvalidInput();
    error InvalidOutputA();
    
    module public immutable MODULE = module(address IEulerMarkets);  //fill in address
    IEERC20 public immutable eToken = IEERC20(address IEulerEToken);
    dtBorrow public immutable DTBORROW = dtBorrow(address EulerDTtoken)
    
     /**
     * @notice Set the address of RollupProcessor.sol
     * @param _rollupProcessor Address of RollupProcessor.sol
     */
     
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}
    
    receive() external payable {}
    
    //Approve the deposit token(_collateral), and approve the token you're going to borrow(_borrowToken)
    
    function performApprovals(address _collateral, address _borrowToken) external {
    
        if (MODULE.underlyingToAssetConfig(_collateral) <= 0) revert MarketNotListed();   //checks if token is 'collateral asset'
        if (_borrowToken == address(0)) revert InvalidInput();                            // checks if token exists 
        IERC20(_collateral).approve(EULER_MAINNET_addr, type(uint).max);
        IERC20(_borrowToken).approve(EULER_MAINNET_addr, type(uint).max);                 //need to fill in EULER_MAINNET address!
        IERC20(_collateral).safeApprove(ROLLUP_PROCESSOR, type(uint256).max);
        IERC20(_borrowToken).safeApprove(ROLLUP_PROCESSOR, type(uint256).max);
        
             
             }
             
             
             
             
     /**
     * @notice Function for depositing collateral, borrowing and withdrawing the underlying assets
     * @dev This method can only be called from RollupProcessor.sol. If `_auxData` is 0 the deposit flow is executed,
     * if 1 the borrow flow, if 2 the (loan) repay flow, if 3 the withdraw flow.
     *
     * @param _inputAssetA - ERC20
     * @param _outputAssetA - ERC20
     * @param _inputValue - the amount of ERC20 tokens to deposit/borrow,
     * @param _auxData - 0 (deposit), 1 (borrow), 3(repay loan), 4(withdraw underlying assets)
     * @return outputValueA - Amount of ERC20 tokens withdrawed back / amount of ERC20 from the borrow 
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _inputValue,
        uint256,
        uint64 _auxData,
        address _token
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
           if (_outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert ErrorLib.InvalidOutputA();
           if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) revert ErrorLib.InvalidOutputA();
           if (MODULE.underlyingToAssetConfig(_token) <= 0) revert MarketNotListed();   //checks if token is 'collateral asset'
           eToken collateralEToken = eToken(MODULE.underlyingToEToken(_token));
           collateralEToken.deposit(0, _inputValue);
           MODULE.enterMarket(0, _token);                                             //enters market (deposited token to be counted as collateral)
           
          }
          
          
        if  (_auxData == 1) {
             if (_outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert ErrorLib.InvalidOutputA();
             DTBORROW borrowedDToken = DTBORROW(MODULE.underlyingToDToken(_token));
             borrowedDToken.borrow(0, _inputValue);
             outputValueA = borrowedDToken.balanceOf(address(this));
             
             }
             
             

        if  (_auxData == 2) {
            if (_outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert ErrorLib.InvalidOutputA();
            DTBORROW borrowedDToken = DTBORROW(MODULE.underlyingToDToken(_token));
            borrowedDToken.repay(0, type(uint).max);
            
            }
            
            
             
           
         if (_auxData == 3) {
            if (_outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert ErrorLib.InvalidOutputA();
            eToken.withdraw(0, type(uint).max);
            outputValueA = eToken.balanceOfUnderlying(address(this));
            
            }
            
            }
            
            
           
           
           
          
       
            
    
        
        
    
    
}

