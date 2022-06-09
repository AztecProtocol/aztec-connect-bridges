// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import { IDefiBridge } from "../../interfaces/IDefiBridge.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AztecTypes } from "../../aztec/AztecTypes.sol";
import {Vault} from "./libraries/Vault.sol";

interface IRibbonFinanceThetaVaultV2 {
    /// @notice Stores the user's pending deposit for the round
    mapping(address => Vault.DepositReceipt) public depositReceipts;

    /// @notice Vault's parameters like cap, decimals
    Vault.VaultParams public vaultParams;

    /// @notice Vault's lifecycle state like round and locked amounts
    Vault.VaultState public vaultState;

    /// @notice On every round's close, the pricePerShare value of an rTHETA token is stored
    /// This is used to determine the number of shares to be returned
    /// to a user with their DepositReceipt.depositAmount
    mapping(uint256 => uint256) public roundPricePerShare;

    function deposit(uint256 amount) external;
    function initiateWithdraw(uint256 numShares) external;
    function completeWithdraw() external;
}

contract RibbonFinanceBridgeContract is IDefiBridge {
  using SafeMath for uint256;

  address public immutable rollupProcessor;
  IRibbonFinanceThetaVaultV2 thetaVaultETHCall = IRibbonFinanceThetaVaultV2(0x0FABaF48Bbf864a3947bdd0Ba9d764791a60467A);

  address public immutable WETH = 0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2;

  mapping(address => address) public underlyingToZkRToken;

  constructor(address _rollupProcessor) public {
    rollupProcessor = _rollupProcessor;
    setUnderlyingToZkRToken(WETH);
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
    // INITIALIZATION AND SANITY CHECKS
    require(
        msg.sender == rollupProcessor,
        "RibbonFinanceBridge: INVALID_CALLER"
    );

    Vault.DepositReceipt depositReceipt;
    // RibbonThetaVaultV2 ETH Call vault (deposit/withdraw WETH)
    if (inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 && inputAssetA.erc20Address == WETH) {
      // TODO: confirm WETH deposited value matches totalInputValue (i.e. normalize denomination)
      // 1. Approve totalInputValue of WETH to be transferred from bridge to thetaVaultETHCall
      IERC20(inputAssetA).approve(address(thetaVaultETHCall), totalInputValue);

      // 2. Get number of unredeemed shares before deposit
      depositReceipt = thetaVaultETHCall.depositReceipts[address(this)].unredeemedShares;
      uint256 numSharesBeforeDeposit = depositReceipt.getSharesFromReceipt(
          thetaVaultETHCall.vaultState.round,
          thetaVaultETHCall.roundPricePerShare[depositReceipt.round],
          thetaVaultETHCall.vaultParams.decimals
      );

      // 3. Deposit totalInputValue WETH to the vault
      thetaVaultETHCall.deposit(totalInputValue);

      // 4. Get number of unredeemed shares after deposit
      depositReceipt = thetaVaultETHCall.depositReceipts[address(this)].unredeemedShares;
      uint256 numSharesAfterDeposit = depositReceipt.getSharesFromReceipt(
          thetaVaultETHCall.vaultState.round,
          thetaVaultETHCall.roundPricePerShare[depositReceipt.round],
          thetaVaultETHCall.vaultParams.decimals
      );

      // 5. Mint numSharesAfter - numSharesBefore to reflect the # of unredeemed shares
      // created in this interaction
      uint256 diff = numSharesAfterDeposit.sub(numSharesBeforeDeposit);
      IERC20Detailed(underlyingToZkRToken[inputAssetA]).mint(
          address(this),
          diff
      );

      // 6. Approve transfer of minted rTokens to rollup processor
      IERC20Detailed(underlyingToZkRToken[inputAssetA]).approve(
          rollupProcessor,
          diff
      );
    }
  }

  function finalise(
    AztecTypes.AztecAsset calldata inputAssetA,
    AztecTypes.AztecAsset calldata inputAssetB,
    AztecTypes.AztecAsset calldata outputAssetA,
    AztecTypes.AztecAsset calldata outputAssetB,
    uint256 interactionNonce,
    uint64 auxData
  ) external payable override returns (uint256, uint256, bool) {
    require(false);
  }

    function setUnderlyingToZkRToken(address underlyingAsset) external {
        underlyingToZkRToken[underlyingAsset] = address(
            new ZkAToken(aToken.name(), aToken.symbol(), aToken.decimals())
        );
    }
}
