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

/**
 * @title Aztec Connect Bridge for the Euler protocol
 * @notice You can use this contract to get or redeem eTokens.
 * @dev Implementation of the IDefiBridge interface for eTokens.
 */

contract EulerLendingBridge is BridgeBase {
    
    using SafeERC20 for IERC20;

    error MarketNotListed();
    
    IEulerMarkets public immutable markets = IEulerMarkets(0x3520d5a913427E6F0D6A83E07ccD4A4da316e4d3);
    
     /**
     * @notice Set the address of RollupProcessor.sol
     * @param _rollupProcessor Address of RollupProcessor.sol
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}
    
    receive() external payable {}
    
     
     /**
     * @notice Set all the necessary approvals for a given underlying and its eToken.
     * @param _underlyingAsset - underlying asset address
     */
    function preApprove(address _underlyingAsset) external {
         if (markets.underlyingToEToken(_underlyingAsset) == address(0)) revert MarketNotListed();    //checks if asset(address) is listed
         _preApprove(IEulerEToken(_underlyingAsset));
    }
    
    function _preApprove(IEulerEToken _underlyingAsset) private {
        uint256 allowance = _underlyingAsset.allowance(address(this), ROLLUP_PROCESSOR);
        if (allowance < type(uint256).max) {
            _underlyingAsset.approve(ROLLUP_PROCESSOR, type(uint256).max - allowance);
        }
            IERC20 underlying = IERC20(_underlyingAsset.underlyingToEToken());
            // Using safeApprove(...) instead of approve(...) here because underlying can be Tether;
            allowance = underlyingToEToken.allowance(address(this), address(_underlyingAsset));
            if (allowance != type(uint256).max) {
                // Resetting allowance to 0 in order to avoid issues with USDT
                underlyingToEToken.safeApprove(address(_underlyingAsset), 0);
                underlyingToEToken.safeApprove(address(_underlyingAsset), type(uint256).max);
            }
            allowance = underlyingToEToken.allowance(address(this), ROLLUP_PROCESSOR);
            if (allowance != type(uint256).max) {
                // Resetting allowance to 0 in order to avoid issues with USDT
                underlying.safeApprove(ROLLUP_PROCESSOR, 0);
                underlying.safeApprove(ROLLUP_PROCESSOR, type(uint256).max);
            }
        }
    
    
    /**
     * @notice Function which mints and burns eTokens in an exchange for the underlying asset.
     * @dev This method can only be called from RollupProcessor.sol. If `_auxData` is 0 the deposit flow is executed,
     * if 1 withdraw flow.
     *
     * @param _inputAssetA - ERC20 (deposit), eToken ERC20 (withdraw)
     * @param _outputAssetA - eToken (deposit), ERC20 (withdraw)
     * @param _inputValue - the amount of ERC20 token to deposit, the amount of eToken to burn (withdraw)
     * @param _interactionNonce - interaction nonce as defined in RollupProcessor.sol
     * @param _auxData - 0 (Deposit), 1 (Withdraw)
     * @return outputValueA - the amount of eTokens (Deposit) or ERC20 (Withdraw) transferred to RollupProcessor.sol
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64 _auxData,
        address _underlying
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
            //deposit
            if (_outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert ErrorLib.InvalidOutputA();
            if (markets.underlyingToEToken(_underlying) == address(0)) revert MarketNotListed();    //checks if token is listed an can be deposited
            
            
            IEulerEToken eToken = IEulerEToken(markets.underlyingToEToken(_underlying));
            eToken.deposit(0, _inputValue);                                                              // 0 here means primary account
            outputValueA = eToken.balanceOf(address(this));
            
        } else if (_auxData == 1) {
            //withdraw
            if (_inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert ErrorLib.InvalidInputA();
            
            IEulerEToken eToken = IEulerEToken(markets.underlyingToEToken(_underlying));
            IERC20 tokenOut = IERC20(_outputAssetA.erc20Address);
            eToken.withdraw(0, _inputValue);                                                            // 0 here means primary account
            outputValueA = tokenOut.balanceOf(address(this));
            
            
            } else {
            revert ErrorLib.InvalidAuxData();
        }
    }
    
}    
            
            
