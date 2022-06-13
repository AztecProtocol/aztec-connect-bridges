// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity ^0.8.4;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import {IDefiBridge} from "../../interfaces/IDefiBridge.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import {AztecTypes} from "../../aztec/AztecTypes.sol";
import {IERC4626} from "./Interfaces/IERC4626.sol";
error Unauthorized();

/**
 * @title Aztec Connect Bridge for ERC4626 compatible vaults
 * @author (@johhonn on Github)
 * @notice You can use this contract to stake asset tokens and bridge share tokens for any ERC2626 compatible bride.
 * @dev Implementation of the IDefiBridge interface for IERC4626
 *
 
 */
contract VaultBridge is IDefiBridge, Ownable {
    using SafeMath for uint256;

    address public immutable rollupProcessor;

    constructor(address _rollupProcessor) public {
        rollupProcessor = _rollupProcessor;
    }

    /**
     * @notice Function which stakes or unstakes
     * @dev This method can only be called from the RollupProcessor.sol. If the input asset is the ERC4626 vault asset, staking flow is
     * executed. If input is the vault share token, unstaking. RollupProcessor.sol has to transfer the tokens to the bridge before calling
     * the method. If this is not the case, the function will revert (either in STAKING_CONTRACT.stake(...) or during
     * SB burn).
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
        override
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        )
    {
        // // ### INITIALIZATION AND SANITY CHECKS

        if (msg.sender != rollupProcessor) revert Unauthorized();

        if (testPair(outputAssetA.erc20Address, inputAssetA.erc20Address)) {
            outputValueA = enter(outputAssetA.erc20Address, inputAssetA.erc20Address, totalInputValue);
        } else if (testPair(inputAssetA.erc20Address, outputAssetA.erc20Address)) {
            outputValueA = exit(inputAssetA.erc20Address, outputAssetA.erc20Address, totalInputValue);
        } else {
            revert("invalid vault token pair address");
        }
    }

    /**
     * @notice Function which test whether a token is a vaild asset for a given vault
     * @dev This method is used to check whether input and output assets are matching vault share/asset pairs
     *
     * @param vault address of erc4626 vault
     * @param asset address of the vault asset token
     *
     */
    function testPair(address vault, address asset) public returns (bool) {
        try IERC4626(a).asset() returns (IERC20 token) {
            return address(token) == b;
        } catch {
            return false;
        }
    }

    /**
     * @notice Internal Function used to stake
     * @dev This method deposits an exact amount of asset into an erc4626 vault then approves the rollup processor
     *
     * @param vault address of erc4626 vault
     * @param token address of the vault asset token
     * @param amount amount of an asset to be burned
   
     */
    // enter by deposit exact assets
    function enter(
        address vault,
        address token,
        uint256 amount
    ) internal returns (uint256) {
        IERC20 depositToken = IERC20(token);
        // depositToken.approve(vault, amount);
        uint256 prev = IERC4626(vault).balanceOf(address(this));
        IERC4626(vault).deposit(amount, address(this));
        uint256 _after = IERC4626(vault).balanceOf(address(this));
        // IERC4626(vault).approve(rollupProcessor, _after.sub(prev));
        return _after.sub(prev);
    }

    /**
     * @notice Internal Function used to unstake
     * @dev This method redeems an exact number of shares into an erc4626 vault then approves the rollup processor
     *
     * @param vault address of erc4626 vault
     * @param token address of the vault asset
     * @param amount amount of shares to be redeemed
     *
     */
    function exit(
        address vault,
        address token,
        uint256 amount
    ) internal returns (uint256) {
        IERC20 withdrawToken = IERC20(token);
        uint256 prev = withdrawToken.balanceOf(address(this));
        IERC4626(vault).redeem(amount, msg.sender, address(this));
        uint256 _after = withdrawToken.balanceOf(address(this));
        //withdrawToken.approve(rollupProcessor, _after.sub(prev));
        return _after.sub(prev);
    }

    /**
     * @notice Internal Function used to preapprove vault pairs
     * @param vault address of erc4626 vault
     * @param token address of the vault asset
     */
    function approvePair(address vault, address token) public {
        IERC20(token).approve(vault, type(uint256).max);
        IERC20(vault).approve(rollupProcessor, type(uint256).max);
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
