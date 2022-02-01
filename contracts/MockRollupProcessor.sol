// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.8.0 <=0.8.10;
pragma abicoder v2;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { IDefiBridge } from "./interfaces/IDefiBridge.sol";
import { DefiBridgeProxy } from "./DefiBridgeProxy.sol";
import { AztecTypes } from "./AztecTypes.sol";
import { IERC20 } from "./interfaces/IERC20Permit.sol";

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

  bytes4 private constant TRANSFER_FROM_SELECTOR = bytes4(keccak256('transferFrom(address,address,uint256)'));
  mapping(uint256 => uint256) ethPayments;
  // We need to cap the amount of gas sent to the DeFi bridge contract for two reasons.
  // 1: To provide consistency to rollup providers around costs.
  // 2: To prevent griefing attacks where a bridge consumes all our gas.
  uint256 private gasSentToBridgeProxy = 300000;

  // DEFI_BRIDGE_PROXY_CONVERT_SELECTOR = function signature of:
  //   function convert(
  //       address,
  //       AztecTypes.AztecAsset memory inputAssetA,
  //       AztecTypes.AztecAsset memory inputAssetB,
  //       AztecTypes.AztecAsset memory outputAssetA,
  //       AztecTypes.AztecAsset memory outputAssetB,
  //       uint256 totalInputValue,
  //       uint256 interactionNonce,
  //       uint256 auxData,
  //       uint256 ethPaymentsSlot)
  // N.B. this is the selector of the 'convert' function of the DefiBridgeProxy contract.
  //      This has a different interface to the IDefiBridge.convert function
  bytes4 private constant DEFI_BRIDGE_PROXY_CONVERT_SELECTOR = 0xffd8e7b7;
  event AztecBridgeInteraction(
    address indexed bridgeAddress,
    uint256 outputValueA,
    uint256 outputValueB,
    bool isAsync
  );

  function receiveEthFromBridge(uint256 interactionNonce) external payable {
    ethPayments[interactionNonce] += msg.value;
  }

  mapping(uint256 => DefiInteraction) private defiInteractions;

  constructor(address _bridgeProxyAddress) {
    bridgeProxy = DefiBridgeProxy(_bridgeProxyAddress);
  }

  function transferTokensAsync(
    address bridgeContract,
    AztecTypes.AztecAsset memory asset,
    uint256 outputValue,
    uint256 interactionNonce
  ) internal {
    if (asset.assetType == AztecTypes.AztecAssetType.ETH) {
      require(
        outputValue == ethPayments[interactionNonce],
        "Rollup Processor: INSUFFICEINT_ETH_PAYMENT"
      );
      ethPayments[interactionNonce] = 0;
    } else if (
      asset.assetType == AztecTypes.AztecAssetType.ERC20 && outputValue > 0
    ) {
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
    require(
      interaction.bridgeAddress != address(0),
      "Rollup Contract: UNKNOWN_NONCE"
    );
    bool isReady = IDefiBridge(interaction.bridgeAddress).canFinalise(
      interaction.interactionNonce
    );
    require(isReady, "Rollup Contract: BRIDGE_NOT_READY");
    (uint256 outputValueA, uint256 outputValueB) = IDefiBridge(
      interaction.bridgeAddress
    ).finalise(
        interaction.inputAssetA,
        interaction.inputAssetB,
        interaction.outputAssetA,
        interaction.outputAssetB,
        interaction.interactionNonce,
        uint64(interaction.auxInputData)
      );
    console.log("Completed");

    if (
      outputValueB > 0 &&
      interaction.outputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED
    ) {
      require(false, "Non-zero output value on non-existant asset!");
    }
    if (outputValueA == 0 && outputValueB == 0) {
      // issue refund.
      transferTokensAsync(
        address(interaction.bridgeAddress),
        interaction.inputAssetA,
        interaction.totalInputValue,
        interaction.interactionNonce
      );
    } else {
      console.log("Transferring");
      // transfer output tokens to rollup contract
      transferTokensAsync(
        address(interaction.bridgeAddress),
        interaction.outputAssetA,
        outputValueA,
        interaction.interactionNonce
      );
      transferTokensAsync(
        address(interaction.bridgeAddress),
        interaction.outputAssetB,
        outputValueB,
        interaction.interactionNonce
      );
      console.log("Transferred");
    }

    emit AztecBridgeInteraction(
      interaction.bridgeAddress,
      outputValueA,
      outputValueB,
      false
    );
  }

  struct BridgeResult {
    uint256 outputValueA;
    uint256 outputValueB;
    bool isAsync;
    bool success;
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
    )
  {
    require(
      defiInteractions[interactionNonce].auxInputData == 0,
      "Rollup Contract: INTERACTION_ALREADY_EXISTS"
    );
    defiInteractions[interactionNonce] = DefiInteraction(
      bridgeAddress,
      inputAssetA,
      inputAssetB,
      outputAssetA,
      outputAssetB,
      totalInputValue,
      interactionNonce,
      auxInputData
    );

    uint256 ethPayments_slot;

    assembly {
      ethPayments_slot := ethPayments.slot
    }
    (bool success, bytes memory result) = address(bridgeProxy).delegatecall(
      abi.encodeWithSelector(
        DEFI_BRIDGE_PROXY_CONVERT_SELECTOR,
        bridgeAddress,
        inputAssetA,
        inputAssetB,
        outputAssetA,
        outputAssetB,
        totalInputValue,
        interactionNonce,
        auxInputData,
        ethPayments_slot
      )
    );
    (outputValueA, outputValueB, isAsync) = abi.decode(
      result,
      (uint256, uint256, bool)
    );

    emit AztecBridgeInteraction(
      bridgeAddress,
      outputValueA,
      outputValueB,
      isAsync
    );
  }
}
