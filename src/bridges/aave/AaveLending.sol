// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import {IDefiBridge} from "../../interfaces/IDefiBridge.sol";
import {ILendingPoolAddressesProvider} from "./interfaces/ILendingPoolAddressesProvider.sol";
import {IERC20Detailed, IERC20} from "./interfaces/IERC20.sol";
import {IPool} from "./interfaces/IPool.sol";
import {IScaledBalanceToken} from "./interfaces/IScaledBalanceToken.sol";

import {AztecTypes} from "../../aztec/AztecTypes.sol";

import {ZkAToken, IZkAToken} from "./ZkAToken.sol";
import {WadRayMath} from "./libraries/WadRayMath.sol";

import {DataTypes} from "./DataTypes.sol";

contract AaveLendingBridge is IDefiBridge {
    using SafeMath for uint256;
    using WadRayMath for uint256;

    address public immutable rollupProcessor;
    address public weth;

    ILendingPoolAddressesProvider addressesProvider;

    mapping(address => address) public underlyingToZkAToken;

    constructor(address _rollupProcessor, address _addressesProvider) {
        rollupProcessor = _rollupProcessor;
        // needed in case AAVE governance changes the lending pool address
        addressesProvider = ILendingPoolAddressesProvider(_addressesProvider);
    }

    // sets underlying address to zkAToken address in underlyingToZkAToken map
    function setUnderlyingToZkAToken(address underlyingAsset) external {
        IPool pool = IPool(addressesProvider.getLendingPool());

        IERC20Detailed aToken = IERC20Detailed(pool.getReserveData(underlyingAsset).aTokenAddress);

        require(address(aToken) != address(0), "AaveLendingBridge: NO_LENDING_POOL");
        require(underlyingToZkAToken[underlyingAsset] == address(0), "AaveLendingBridge: ZK_TOKEN_SET");

        // TODO add AztecAAVEBridge token to name / symbol
        underlyingToZkAToken[underlyingAsset] = address(
            new ZkAToken(aToken.name(), aToken.symbol(), aToken.decimals())
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
        require(msg.sender == rollupProcessor, "AaveLendingBridge: INVALID_CALLER");
        require(inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20, "AaveLendingBridge: INPUT_ASSET_NOT_ERC20");
        require(outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20, "AaveLendingBridge: OUTPUT_ASSET_NOT_ERC20");

        address zkAtokenAddress = underlyingToZkAToken[inputAssetA.erc20Address];
        if (zkAtokenAddress == address(0)) {
            // we are withdrawing zkATokens for underlying
            outputValueA = _exit(outputAssetA.erc20Address, totalInputValue);
        } else {
            // we are depositing underlying for zkATokens
            outputValueA = _enter(inputAssetA.erc20Address, totalInputValue);
        }
    }

    function _enter(address inputAsset, uint256 amount) internal returns (uint256) {
        IPool pool = IPool(addressesProvider.getLendingPool());
        IScaledBalanceToken aToken = IScaledBalanceToken(pool.getReserveData(inputAsset).aTokenAddress);
        require(address(aToken) != address(0), "AaveLendingBridge: NO_LENDING_POOL");
        require(underlyingToZkAToken[inputAsset] != address(0), "AaveLendingBridge: NO_ZK_TOKEN_POOL");

        // 1. Read the scaled balance from the lending pool
        uint256 scaledBalance = aToken.scaledBalanceOf(address(this));

        // 2. Approve totalInputValue to be lent on AAVE
        IERC20Detailed(inputAsset).approve(address(pool), amount);

        // 3. Lend totalInputValue of inputAssetA on AAVE lending pool
        pool.deposit(inputAsset, amount, address(this), 0);

        // 4. Mint the difference between the scaled balance at the start of the interaction and after the deposit as our zkAToken
        uint256 diff = aToken.scaledBalanceOf(address(this)).sub(scaledBalance);
        IERC20Detailed(underlyingToZkAToken[inputAsset]).mint(address(this), diff);

        IERC20Detailed(underlyingToZkAToken[inputAsset]).approve(rollupProcessor, diff);
        return diff;
    }

    function _exit(address outputAsset, uint256 scaledAmount) internal returns (uint256) {
        IPool pool = IPool(addressesProvider.getLendingPool());
        // get aToken contract of corresponding underlying aTokenAddress
        IERC20 aToken = IERC20(pool.getReserveData(outputAsset).aTokenAddress);

        // 1. Compute the amount from the scaledAmount supplied
        uint256 underlyingAmount = scaledAmount.rayMul(pool.getReserveNormalizedIncome(outputAsset));

        // 2. Lend totalInputValue of inputAssetA on AAVE lending pool and return the amount of tokens
        uint256 outputValue = pool.withdraw(outputAsset, underlyingAmount, address(this));

        IERC20Detailed(outputAsset).approve(rollupProcessor, outputValue);

        // 3. Burn the supplied amount of zkAToken as this has now been withdrawn
        IZkAToken(underlyingToZkAToken[outputAsset]).burn(scaledAmount);

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
