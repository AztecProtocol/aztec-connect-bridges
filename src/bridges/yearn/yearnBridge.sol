// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';

import {IDefiBridge} from '../../interfaces/IDefiBridge.sol';
import {VaultAPI} from './interfaces/VaultAPI.sol';
import {RegistryAPI} from './interfaces/RegistryAPI.sol';
import {IERC20Detailed, IERC20} from './interfaces/IERC20.sol';

import {AztecTypes} from '../../aztec/AztecTypes.sol';

import {ZkVToken, IZkVToken} from './ZkVToken.sol';
import {WadRayMath} from './libraries/WadRayMath.sol';

contract YearnLendingBridge is IDefiBridge {
    using SafeMath for uint256;
    using WadRayMath for uint256;

    address public immutable rollupProcessor;
    address public weth;

    RegistryAPI addressesProvider;

    mapping(address => address) public underlyingToZkVToken;

    constructor(address _rollupProcessor, address _addressesProvider) {
        rollupProcessor = _rollupProcessor;
        // needed in case AAVE governance changes the lending pool address
        addressesProvider = RegistryAPI(_addressesProvider);
    }

    function setUnderlyingToZkVToken(address underlyingAsset) external {
        IERC20Detailed vToken = IERC20Detailed(VaultAPI((addressesProvider.latestVault(underlyingAsset))).token());

        require(address(vToken) != address(0), 'AaveLendingBridge: NO_LENDING_POOL');
        require(underlyingToZkVToken[underlyingAsset] == address(0), 'AaveLendingBridge: ZK_TOKEN_SET');

        // TODO add AztecAAVEBridge token to name / symbol
        underlyingToZkVToken[underlyingAsset] = address(
            new ZkVToken(vToken.name(), vToken.symbol(), vToken.decimals())
        );
    }

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
        // ### INITIALIZATION AND SANITY CHECKS
        require(msg.sender == rollupProcessor, 'AaveLendingBridge: INVALID_CALLER');
        require(inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20, 'AaveLendingBridge: INPUT_ASSET_NOT_ERC20');
        require(outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20, 'AaveLendingBridge: OUTPUT_ASSET_NOT_ERC20');

        address zkVtokenAddress = underlyingToZkVToken[inputAssetA.erc20Address];
        if (zkVtokenAddress == address(0)) {
            // we are withdrawing zkATokens for underlying
            outputValueA = _exit(outputAssetA.erc20Address, totalInputValue);
        } else {
            // we are depositing underlying for zkATokens
            outputValueA = _enter(inputAssetA.erc20Address, totalInputValue);
        }
    }

    function _enter(address inputAsset, uint256 amount) internal returns (uint256) {
        VaultAPI vault = VaultAPI(addressesProvider.latestVault(inputAsset));
        IERC20 vaultToken = IERC20(vault.token());

        require(address(vaultToken) != address(0), 'AaveLendingBridge: NO_LENDING_POOL');
        // require(underlyingToZkVToken[vaultToken] != address(0), 'AaveLendingBridge: NO_ZK_TOKEN_POOL');

        // 1. Read the scaled balance from the lending pool
        uint256 scaledBalance = vaultToken.balanceOf(address(this));

        // 2. Approve totalInputValue to be lent on AAVE
        IERC20Detailed(inputAsset).approve(address(vault), amount);
        IERC20Detailed(inputAsset).transferFrom(msg.sender, address(this), amount);
        // 3. Lend totalInputValue of inputAssetA on AAVE lending pool
        uint256 shares = vault.deposit(amount);

        // 4. Mint the difference between the scaled balance at the start of the interaction and after the deposit as our zkAToken
        uint256 diff = vaultToken.balanceOf(address(this)).sub(scaledBalance);
        IERC20Detailed(underlyingToZkVToken[inputAsset]).mint(address(this), diff);

        IERC20Detailed(underlyingToZkVToken[inputAsset]).approve(rollupProcessor, diff);
        return diff;
    }

    function _exit(address outputAsset, uint256 scaledAmount) internal returns (uint256) {
        VaultAPI vault = VaultAPI(addressesProvider.latestVault(outputAsset));
        IERC20 vaultToken = IERC20(vault.token());

        // 1. Compute the amount from the scaledAmount supplied
        //uint256 underlyingAmount = scaledAmount.rayMul(pool.getReserveNormalizedIncome(outputAsset));

        // 2. Lend totalInputValue of inputAssetA on AAVE lending pool and return the amount of tokens
        // uint256 outputValue = pool.withdraw(outputAsset, underlyingAmount, address(this));
        uint256 outputValue = vault.withdraw(scaledAmount);
        IERC20Detailed(outputAsset).approve(rollupProcessor, outputValue);

        // 3. Burn the supplied amount of zkAToken as this has now been withdrawn
        IZkVToken(underlyingToZkVToken[outputAsset]).burn(scaledAmount);

        return outputValue;
    }

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

    function claimLiquidityRewards(address a) external {
        /*
      // Ideas
       1. Dump per enter and exit, add to deposit and create a rewards index : Everyone gets a better interest rate, not exact. Don't get AAVE TOken
       2. Use outputAssetB as a virtual asset and let Whales claim their pro-rata share of the rewards : Only whales can do this, get AAVE Token
       3. Use outputAssetB as a virtual asset. Aztec to create a rewards proof later... or not.
       4. Send to Aztec Fee Contract - swap stkAAVE for AAVE - swap for ETH and use to subsidize.
       5. Send to Gitcoin grants
       */
    }
}
