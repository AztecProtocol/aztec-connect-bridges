// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity ^0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {IERC4626} from "../../interfaces/erc4626/IERC4626.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";

/**
 * @title Aztec Connect Bridge for ERC4626 compatible vaults
 * @author (@johhonn on Github)
 * @notice You can use this contract to stake asset tokens and bridge share tokens for any ERC2626 compatible bridge.
 * @dev Implementation of the IDefiBridge interface for IERC4626
 *
 
 */
contract VaultBridge is BridgeBase {
    using SafeERC20 for IERC20;

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    /**
     * @notice Function which stakes or unstakes
     * @dev This method can only be called from the RollupProcessor.sol. If the input asset is the ERC4626 vault asset, staking flow is
     * executed. If input is the vault share token, unstaking. RollupProcessor.sol has to transfer the tokens to the bridge before calling
     * the method. If this is not the case, the function will revert (either in STAKING_CONTRACT.stake(...) or during
     * SB burn).This contract is stateless and cannot hold tokens thus is safe to approve.
     *
     * @param _inputAssetA - Vault asset (Staking) or Vault Address (Unstaking)
     * @param _outputAssetA - Vault Address (Staking) or Vault asset (UnStaking)
     * @param _totalInputValue - the amount of assets to stake or shares to unstake
     * @return _outputValueA - the amount of shares (Staking) or assets (Unstaking) minted/transferred to the RollupProcessor.sol
     *
     */
    function convert(
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory,
        AztecTypes.AztecAsset memory _outputAssetA,
        AztecTypes.AztecAsset memory,
        uint256 _totalInputValue,
        uint256,
        uint64,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 _outputValueA,
            uint256,
            bool
        )
    {
        // // ### INITIALIZATION AND SANITY CHECKS

        if (isValidPair(_outputAssetA.erc20Address, _inputAssetA.erc20Address)) {
            _outputValueA = _enter(_outputAssetA.erc20Address, _totalInputValue);
        } else if (isValidPair(_inputAssetA.erc20Address, _outputAssetA.erc20Address)) {
            _outputValueA = _exit(_inputAssetA.erc20Address, _totalInputValue);
        } else {
            revert ErrorLib.InvalidInput();
        }
    }

    /**
     * @notice Public Function used to preapprove vault pairs
     * @param _vault address of erc4626 vault
     * @param _token address of the vault asset
     */
    function approvePair(address _vault, address _token) public {
        IERC20(_token).safeApprove(address(_vault), 0);
        IERC20(_token).safeApprove(address(_vault), type(uint256).max);
        IERC20(_token).safeApprove(address(ROLLUP_PROCESSOR), 0);
        IERC20(_token).safeApprove(address(ROLLUP_PROCESSOR), type(uint256).max);
        IERC20(_vault).approve(ROLLUP_PROCESSOR, type(uint256).max);
    }

    /**
     * @notice Internal Function used to stake
     * @dev This method deposits an exact amount of asset into an erc4626 vault
     *
     * @param _vault address of erc4626 vault
     * @param _amount amount of an asset to be burned
     * @return - the amount of shares earned by depositing which will equal the convert output value
     */
    // enter by deposit exact assets
    function _enter(address _vault, uint256 _amount) internal returns (uint256) {
        return IERC4626(_vault).deposit(_amount, address(this));
    }

    /**
     * @notice Internal Function used to unstake
     * @dev This method redeems an exact number of shares from an erc4626 vault
     *
     * @param _vault address of erc4626 vault
     * @param _amount amount of shares to be redeemed
     * @return - the amount of asset tokens withdrawn by redeeming shares
     */
    function _exit(address _vault, uint256 _amount) internal returns (uint256) {
        return IERC4626(_vault).redeem(_amount, address(this), address(this));
    }

    /**
     * @notice Function which checks whether a token is a vaild asset for a given vault
     * @dev This method is used to check whether input and output assets are matching vault share/asset pairs
     *
     * @param _vault address of erc4626 vault
     * @param _asset address of the vault asset token
     * @return - boolean of whether an asset is a valid token for a vault
     */
    function _isValidPair(address _vault, address _asset) internal view returns (bool) {
        try IERC4626(_vault).asset() returns (IERC20 token) {
            return address(_token) == _asset;
        } catch {
            return false;
        }
    }
}
