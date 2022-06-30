// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";

import {ErrorLib} from "./../base/ErrorLib.sol";
import {BridgeBase} from "./../base/BridgeBase.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IEulerEToken} from "../../interfaces/euler/IEulerEToken.sol";
import {IEulerMarkets} from "../../interfaces/euler/IEulerMarkets.sol";
import {IEulerDToken} from "../../interfaces/euler/IEulerDToken.sol";

/**
 * @title Aztec Connect Bridge for the Euler protocol
 * @notice You can use this contract to deposit collateral and borrow.
 * @dev Implementation of the IDefiBridge interface for eTokens.
 */

contract EulerLendingBridge is BridgeBase {
    
    using SafeERC20 for IERC20;

    error MarketNotListed();
    
    IEulerMarkets markets = IEulerMarkets(EULER_MAINNET_MARKETS);
    
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}
    
    receive() external payable {}
    
    
    function performApproval(address _underlyingAsset) public override(IEulerEToken) {
             
       if (markets.underlyingToEToken(_underlyingAsset) == address(0)) revert MarketNotListed();    //checks if asset(address) is listed
       
       // SafeApprove not needed if it follows IERC20;
       IERC20(_underlyingAsset).approve(ROLLUP_PROCESSORT, type(uint256).max);                          //need to add address 
       IERC20(_underlyingAsset).approve(EULER_MAINNET, type(uint256).max);  
       
       // safeApprove, because Underlying can be tether
       IERC20(_underlyingAsset).safeApprove(EULER_MAINNET, 0);
       IERC20(_underlyingAsset).safeApprove(EULER_MAINNET, type(uint256).max);                       //need to add address 
       
       // safeApprove, because Underlying can be Tether
       IERC20(_underlyingAsset).safeApprove(ROLLUP_PROCESSOR, 0);
       IERC20(_underlyingAsset).safeApprove(ROLLUP_PROCESSOR, type(uint256).max);                    //need to add address
    
    }
    
    
    function preApprove(address _underlyingAsset) external {
         if (markets.underlyingToEToken(_underlyingAsset) == address(0)) revert MarketNotListed();    //checks if asset(address) is listed
         _preApprove(ICERC20(_underlyingAsset));
    }
    
    function _preApprove(ICERC20 _underlyingAsset) private {
        uint256 allowance = _underlyingAsset.allowance(address(this), ROLLUP_PROCESSOR);
        if (allowance < type(uint256).max) {
            _underlyingAsset.approve(ROLLUP_PROCESSOR, type(uint256).max - allowance);
        }
            IERC20 underlying = IERC20(_underlyingAsset.underlyingToEToken());
            // Using safeApprove(...) instead of approve(...) here because underlying can be Tether;
            allowance = underlying.allowance(address(this), address(_cToken));
            if (allowance != type(uint256).max) {
                // Resetting allowance to 0 in order to avoid issues with USDT
                underlying.safeApprove(address(_cToken), 0);
                underlying.safeApprove(address(_cToken), type(uint256).max);
            }
            allowance = underlying.allowance(address(this), ROLLUP_PROCESSOR);
            if (allowance != type(uint256).max) {
                // Resetting allowance to 0 in order to avoid issues with USDT
                underlying.safeApprove(ROLLUP_PROCESSOR, 0);
                underlying.safeApprove(ROLLUP_PROCESSOR, type(uint256).max);
            }
        }
    }
    
    
    
    
    
    
    
  
}
    
    
    
    
    
    

