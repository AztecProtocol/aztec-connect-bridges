// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity ^0.8.4;
pragma experimental ABIEncoderV2;

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

    error AssetMustBeEmpty();

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    /**
     * @notice Function which stakes or unstakes
     * @dev This method can only be called from the RollupProcessor.sol. If the input asset is the ERC4626 vault asset, staking flow is
     * executed. If input is the vault share token, unstaking. RollupProcessor.sol has to transfer the tokens to the bridge before calling
     * the method. If this is not the case, the function will revert (either in STAKING_CONTRACT.stake(...) or during
     * SB burn).This contract is stateless and cannot hold tokens thus is safe to approve.
     *
     * @param inputAssetA - Vault asset (Staking) or Vault Address (Unstaking)
     * @param outputAssetA - Vault Address (Staking) or Vault asset (UnStaking)
     * @param totalInputValue - the amount of assets to stake or shares to unstake
     * @return outputValueA - the amount of shares (Staking) or assets (Unstaking) minted/transferred to
     * the RollupProcessor.sol
     */
    function convert(
        AztecTypes.AztecAsset memory inputAssetA,
        AztecTypes.AztecAsset memory inputAssetB,
        AztecTypes.AztecAsset memory outputAssetA,
        AztecTypes.AztecAsset memory outputAssetB,
        uint256 totalInputValue,
        uint256 interactionNonce,
        uint64 auxData,
        address rollupBeneficiary
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
        // // ### INITIALIZATION AND SANITY CHECKS
        if (
            outputAssetB.assetType != AztecTypes.AztecAssetType.NOT_USED ||
            inputAssetB.assetType != AztecTypes.AztecAssetType.NOT_USED
        ) revert AssetMustBeEmpty();

        if (isValidPair(outputAssetA.erc20Address, inputAssetA.erc20Address)) {
            outputValueA = _enter(outputAssetA.erc20Address, totalInputValue);
        } else if (isValidPair(inputAssetA.erc20Address, outputAssetA.erc20Address)) {
            outputValueA = _exit(inputAssetA.erc20Address, totalInputValue);
        } else {
            revert ErrorLib.InvalidInput();
        }
    }

    /**
     * @notice Public Function used to preapprove vault pairs
     * @param vault address of erc4626 vault
     * @param token address of the vault asset
     * @param safeApprove bool determining whether the asset will use safe approve or not
     */
    function approvePair(
        address vault,
        address token,
        bool safeApprove
    ) public {
        if (safeApprove) {
            IERC20(token).safeApprove(address(token), 0);
            IERC20(token).safeApprove(address(token), type(uint256).max);
        } else {
            IERC20(token).approve(ROLLUP_PROCESSOR, type(uint256).max);
            IERC20(token).approve(vault, type(uint256).max);
        }

        IERC20(vault).approve(ROLLUP_PROCESSOR, type(uint256).max);
    }

    /**
     * @notice Function which checks whether a token is a vaild asset for a given vault
     * @dev This method is used to check whether input and output assets are matching vault share/asset pairs
     *
     * @param vault address of erc4626 vault
     * @param asset address of the vault asset token
     *
     */
    function isValidPair(address vault, address asset) internal returns (bool) {
        try IERC4626(vault).asset() returns (IERC20 token) {
            return address(token) == asset;
        } catch {
            return false;
        }
    }

    /**
     * @notice Internal Function used to stake
     * @dev This method deposits an exact amount of asset into an erc4626 vault
     *
     * @param vault address of erc4626 vault     
     * @param amount amount of an asset to be burned
   
     */
    // enter by deposit exact assets
    function _enter(address vault, uint256 amount) internal returns (uint256) {
        return IERC4626(vault).deposit(amount, address(this));
    }

    /**
     * @notice Internal Function used to unstake
     * @dev This method redeems an exact number of shares into an erc4626 vault
     *
     * @param vault address of erc4626 vault
     * @param amount amount of shares to be redeemed
     *
     */
    function _exit(address vault, uint256 amount) internal returns (uint256) {
        return IERC4626(vault).redeem(amount, address(this), address(this));
    }

    // @notice This function always reverts because this contract does not implement async flow.
    function finalise(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata inputAssetB,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata outputAssetB,
        uint256 interactionNonce,
        uint64 auxData
    )
        external
        payable
        override
        returns (
            uint256,
            uint256,
            bool
        )
    {
        require(false);
    }
}
