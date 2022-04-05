// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import { IDefiBridge } from "../../interfaces/IDefiBridge.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import { AztecTypes } from "../../aztec/AztecTypes.sol";

contract RibbonFinanceBridgeContract is IDefiBridge {
  using SafeMath for uint256;

  address public immutable rollupProcessor;

  constructor(address _rollupProcessor) public {
    rollupProcessor = _rollupProcessor;
  }

  /*
    1. Deposit (with a DepositReceipt if exists)
    2. Get back a DepositReceipt
    3. Store DepositReceipt returned from ribbon deposit call

    Ribbon Deposit:
    https://sourcegraph.com/github.com/ribbon-finance/ribbon-v2/-/blob/contracts/vaults/BaseVaults/base/RibbonVault.sol?L315
    --> 
    https://sourcegraph.com/github.com/ribbon-finance/ribbon-v2/-/blob/contracts/vaults/BaseVaults/base/RibbonVault.sol?L356
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
    // INITIALIZATION AND SANITY CHECKS
    require(
        msg.sender == rollupProcessor,
        "RibbonFinanceBridge: INVALID_CALLER"
    );
    require(
        inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20,
        "RibbonFinanceBridge: INPUT_ASSET_NOT_ERC20"
    );
    require(
        outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20,
        "RibbonFinanceBridge: OUTPUT_ASSET_NOT_ERC20"
    );

    // main code
    // RibbonThetaVaultV2 ETH Call vault (deposit/withdraw ETH)
    if (inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
      // deposit flow
      _depositIntoThetaETHCallV2Vault(totalInputValue);
      outputValueA = _getNumUnredeemedShares(thetaEthCallV2VaultContract, assetToShares(amount));
    } else if (outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
      // withdraw flow
      _withdrawFromThetaETHCallV2Vault(totalInputValue);
      outputValueA = _getNumUnredeemedShares(thetaEthCallV2VaultContract, assetToShares(amount));      
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

	function _depositIntoThetaEthCallV2Vault(uint256 amount) {
		ribbonFinanceContract.deposit(amount);
	}

	function _withdrawFromThetaEthCallV2Vault(uint256 amount) {
		ribbonFinanceContract.withdraw(amount);
	}  

	function _getNumUnredeemedShares(
    contract vault,
    uint256 assetPerShare
    ) returns (uint256) {
      return getSharesFromReceipt(
        vault.depositReceipts[address(this)],
        vault.vaultState.round,
        assetPerShare,
        vault.vaultParams.decimals
      ).unredeemedShares;
  }

}
