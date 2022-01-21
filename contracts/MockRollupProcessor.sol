// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { IDefiBridge } from "./interfaces/IDefiBridge.sol";
import { DefiBridgeProxy } from "./DefiBridgeProxy.sol";
import { AztecTypes } from "./Types.sol";
import { IERC20 } from "./interfaces/IERC20Permit.sol";
// import { IRollupProcessor } from "./interfaces/IRollupProcessor.sol";

import "hardhat/console.sol";

contract MockRollupProcessor {
  DefiBridgeProxy private bridgeProxy;

  struct DefiInteraction {
    address bridgeAddress;
    AztecTypes.AztecAsset inputAssetA;
    AztecTypes.AztecAsset inputAssetB;
    AztecTypes.AztecAsset outputAssetA;
    AztecTypes.AztecAsset outputAssetB;
    uint256 totalInputValue;
    uint256 interactionNonce;
    uint256 auxInputData; // (auxData)
  }

  bytes4 private constant TRANSFER_FROM_SELECTOR = 0x23b872dd; // bytes4(keccak256('transferFrom(address,address,uint256)'));
  mapping(address => mapping(uint256 => uint256)) ethPayments;

  event AztecBridgeInteraction(
    address indexed bridgeAddress,
    uint256 outputValueA,
    uint256 outputValueB,
    bool isAsync
  );

  function receiveEthFromBridge(uint256 interactionNonce) external payable {
        ethPayments[msg.sender][interactionNonce] = msg.value;
  }

  mapping(uint256 => DefiInteraction) private defiInteractions;

  constructor(
    address _bridgeProxyAddress
  ) {
    bridgeProxy = DefiBridgeProxy(_bridgeProxyAddress);
  }

  function transferTokensAsync(address bridgeContract, AztecTypes.AztecAsset memory asset, uint256 outputValue, uint256 interactionNonce) internal {
      if (asset.assetType == AztecTypes.AztecAssetType.ETH) {
          require(outputValue == ethPayments[bridgeContract][interactionNonce], 'Rollup Processor: INSUFFICEINT_ETH_PAYMENT');
          ethPayments[bridgeContract][interactionNonce] = 0;
      } else if (asset.assetType == AztecTypes.AztecAssetType.ERC20 && outputValue > 0) {
          uint256 assetId = asset.id;
          address tokenAddress = asset.erc20Address;
          bool success;

          assembly {
              // call token.transferFrom(bridgeAddressId, this, outputValue)
              let mPtr := mload(0x40)
              mstore(mPtr, TRANSFER_FROM_SELECTOR)
              mstore(add(mPtr, 0x04), bridgeContract)
              mstore(add(mPtr, 0x24), address())
              mstore(add(mPtr, 0x44), outputValue)
              success := call(gas(), tokenAddress, 0, mPtr, 0x64, 0x00, 0x20)
              if iszero(success) {
                  returndatacopy(0, 0, returndatasize())
                  revert(0x00, returndatasize())
              }
          }
      }

      // VIRTUAL Assets are not transfered.
  }

  function processAsyncDeFiInteraction(uint256 interactionNonce) external {
    // call canFinalise on the bridge
    // call finalise on the bridge
    DefiInteraction storage interaction = defiInteractions[interactionNonce];
    bool isReady = IDefiBridge(interaction.bridgeAddress).canFinalise(interaction.interactionNonce);
    require(isReady, 'Rollup Contract: BRIDGE_NOT_READY');
      (uint256 outputValueA, uint256 outputValueB) = IDefiBridge(interaction.bridgeAddress).finalise(
        interaction.inputAssetA,
        interaction.inputAssetB,
        interaction.outputAssetA,
        interaction.outputAssetB,
        interaction.interactionNonce,
        uint64(interaction.auxInputData));


    if (outputValueB > 0 && interaction.outputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED)
    {
        require(false, "Non-zero output value on non-existant asset!");
    }
    if (outputValueA == 0 && outputValueB == 0) {
        // issue refund.
        transferTokensAsync(address(interaction.bridgeAddress), interaction.inputAssetA, interaction.totalInputValue, interaction.interactionNonce);
    } else {
        // transfer output tokens to rollup contract
        transferTokensAsync(address(interaction.bridgeAddress), interaction.outputAssetA, outputValueA, interaction.interactionNonce);
        transferTokensAsync(address(interaction.bridgeAddress), interaction.outputAssetB, outputValueB, interaction.interactionNonce);
    }


    emit AztecBridgeInteraction(
      interaction.bridgeAddress,
      outputValueA,
      outputValueB,
      false
    );
  }

  function convert(
    address bridgeAddress,
    AztecTypes.AztecAsset calldata inputAssetA,
    AztecTypes.AztecAsset calldata inputAssetB,
    AztecTypes.AztecAsset calldata outputAssetA,
    AztecTypes.AztecAsset calldata outputAssetB,
    uint256 totalInputValue,
    uint256 interactionNonce,
    uint256 auxInputData // (auxData)
  )
    external
    returns (
      uint256 outputValueA,
      uint256 outputValueB,
      bool isAsync
    ) {
      defiInteractions[interactionNonce] = DefiInteraction(bridgeAddress, 
        inputAssetA,
        inputAssetB,
        outputAssetA,
        outputAssetB,
        totalInputValue,
        interactionNonce,
        auxInputData
      );
      return bridgeProxy.convert(bridgeAddress, inputAssetA, inputAssetB, outputAssetA, outputAssetB, totalInputValue, interactionNonce, auxInputData);
  }  
}