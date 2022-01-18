// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <0.8.11;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { ITranche } from "./ITranche.sol";
import { IERC20Permit } from "./IERC20Permit.sol";

import { IDefiBridge } from "../../interfaces/IDefiBridge.sol";

import { AztecTypes } from "../../Types.sol";

import "hardhat/console.sol";



contract ElementBridge is IDefiBridge {
  using SafeMath for uint256;

  struct Interaction {
    AztecTypes.AztecAsset asset;
    uint256 expiry;
    uint256 quantityPT;
    bool finalised;
  }

  // Tranche factory address for Tranche contract address derivation
  address internal immutable trancheFactory;
  // Tranche bytecode hash for Tranche contract address derivation.
  // This is constant as long as Tranche does not implement non-constant constructor arguments.
  bytes32 internal immutable trancheBytecodeHash;
  // Wrapped position address for DAI stablecoin

  mapping(uint256 => Interaction) private interactions;

  address public immutable rollupProcessor;

  constructor(
    address _rollupProcessor,
    address _trancheFactory,
    bytes32 _trancheBytecodeHash
  ) public {
    rollupProcessor = _rollupProcessor;
    trancheFactory = _trancheFactory;
    trancheBytecodeHash = _trancheBytecodeHash;
  }

  function registerConvergentPoolAddress(
    address _convergentPool,
    address _tranche
  ) external {
    // stores a mapping between tranche address and pool.
    // required to look up the swap info on balancer
  }

  /// @dev This internal function produces the deterministic create2
  ///      address of the Tranche contract from a wrapped position contract and expiration
  /// @param _position The wrapped position contract address
  /// @param _expiration The expiration time of the tranche
  /// @return The derived Tranche contract
  function deriveTranche(address _position, uint256 _expiration)
    internal
    view
    virtual
    returns (ITranche)
  {
    bytes32 salt = keccak256(abi.encodePacked(_position, _expiration));
    bytes32 addressBytes = keccak256(
      abi.encodePacked(bytes1(0xff), trancheFactory, salt, trancheBytecodeHash)
    );
    return ITranche(address(uint160(uint256(addressBytes))));
  }

  function convert(
    AztecTypes.AztecAsset memory inputAssetA,
    AztecTypes.AztecAsset memory inputAssetB,
    AztecTypes.AztecAsset memory outputAssetA,
    AztecTypes.AztecAsset memory outputAssetB,
    uint256 totalInputValue,
    uint256 interactionNonce,
    uint64 auxData
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
    require(msg.sender == rollupProcessor, "ElementBridge: INVALID_CALLER");

    require(
      inputAssetA.id == outputAssetA.id,
      "ElementBridge: ASSET_IDS_NOT_EQUAL"
    );

    require(
      inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20,
      "ElementBridge: NOT_ERC20"
    );

    // ### ASYNC BRIDGE LOGIC

    isAsync = true;

    // outputValueA and outputValueB are already initialised as 0 so no need to set.
    // 1. If there are multiple Element pools for the input asset, the DBC should use the value in the auxData to pick the correct pool expiry.

    // auxData should be a unix timestamp (seconds since 01 Jan 1970)
    // ITranche tranche = deriveTranche(daiWrappedPosition, auxData);

    // 2. Will purchase totalInputValue principal tokens via the Element AMM with the given input asset ERC20

    // Does Balancer require us to approve the tokens being swapped?
    // TODO doesn't work for ETH ???
    // Should we minus a fee here for finalising the bridge at a later date ???

    // ERC20(inputAssetA.address).approve(_balancer, totalInputValue);

    // uint256 principalTokensAmount = _balancer.swap(
    //     IVault.SingleSwap({
    //         poolId: _info.balancerPoolId,
    //         kind: IVault.SwapKind.GIVEN_IN,
    //         assetIn: inputAssetA.erc20Address,
    //         assetOut: IAsset(address(ITranche)),
    //         amount: totalInputValue,
    //         userData: '0x00'
    //     }),
    //     IVault.FundManagement({
    //         sender: address(this), // the bridge has already received the tokens from the rollup so it owns totalInputValue of inputAssetA
    //         fromInternalBalance: false,
    //         recipient: address(this),
    //         toInternalBalance: false
    //     }),
    //     0, // TODO use the auxData to set this, in the short term allow infinite slippage.
    //     block.timestamp
    // );

    // 3. Record the amount of purchased principal tokens against the interaction nonce for this interaction.
    // 4. Record the maturity date against the interaction nonce so this async transaction can be finalised at a later date
    // interactions[interactionNonce] = Interaction(
    //   inputAssetA,
    //   auxData,
    //   principalQuantity,
    //   false
    // );
  }

  function canFinalise(uint256 interactionNonce)
    external
    view
    override
    returns (bool)
  {
    uint256 expiry = interactions[interactionNonce].expiry;
    require(expiry != 0, "ElementBridge: UNKNOWN_NONCE");
    return expiry <= block.timestamp;
  }

  function finalise(
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata,
    uint256,
    uint64
  ) external payable override returns (uint256, uint256) {
    require(false);
  }

  // function finalise(
  //   address inputAsset,
  //   address outputAssetA,
  //   address outputAssetB,
  //   uint256 interactionNonce,
  //   uint32 bitConfig
  // ) external payable override {
  //   Interaction storage interaction = interactions[interactionNonce];
  //   require(interaction.expiry != 0, "ElementBridge: UNKNOWN_NONCE");
  //   require(
  //     interaction.expiry <= block.timestamp,
  //     "ElementBridge: TERM_NOT_REACHED"
  //   );
  //   require(!interaction.finalised, "ElementBridge: ALREADY_FINALISED");
  //   ITranche tranche = deriveTranche(daiWrappedPosition, interaction.expiry);
  //   tranche.withdrawPrincipal(interaction.quantityPT, address(this));
  //   // transfer to rollup etc
  //   interaction.finalised = true;
  // }
}
