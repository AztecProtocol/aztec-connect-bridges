// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { IVault, IAsset } from "../../interfaces/IVault.sol";
import { IPool } from "../../interfaces/IPool.sol";
import { ITranche } from "../../interfaces/ITranche.sol";
import { IERC20Permit, IERC20 } from "../../interfaces/IERC20Permit.sol";
import { IWrappedPosition } from "../../interfaces/IWrappedPosition.sol";

import { IDefiBridge } from "../../interfaces/IDefiBridge.sol";

import { AztecTypes } from "../../Types.sol";

import "hardhat/console.sol";

contract ElementBridge is IDefiBridge {
  struct Interaction {
    address trancheAddress;
    uint64 expiry;
    uint256 quantityPT;
    bool finalised;
  }

  struct Pool {
    address trancheAddress;
    address poolAddress;
    bytes32 poolId;
  }

  // Tranche factory address for Tranche contract address derivation
  address private immutable trancheFactory;
  // Tranche bytecode hash for Tranche contract address derivation.
  // This is constant as long as Tranche does not implement non-constant constructor arguments.
  bytes32 private immutable trancheBytecodeHash; // = 0xf481a073666136ab1f5e93b296e84df58092065256d0db23b2d22b62c68e978d;

  mapping(uint256 => Interaction) private interactions;

  mapping(uint256 => Pool) private pools;

  address public immutable rollupProcessor;

  address private immutable balancerAddress;

  constructor(
    address _rollupProcessor,
    address _trancheFactory,
    bytes32 _trancheBytecodeHash,
    address _balancerVaultAddress
  ) public {
    rollupProcessor = _rollupProcessor;
    trancheFactory = _trancheFactory;
    trancheBytecodeHash = _trancheBytecodeHash;
    balancerAddress = _balancerVaultAddress;
  }

  function registerConvergentPoolAddress(
    address _convergentPool,
    address _wrappedPosition,
    uint32 _expiry
  ) external {
    // stores a mapping between tranche address and pool.
    // required to look up the swap info on balancer
    checkAndStorePoolSpecification(_wrappedPosition, _expiry, _convergentPool);
  }

  /// @dev This internal function produces the deterministic create2
  ///      address of the Tranche contract from a wrapped position contract and expiration
  /// @param _position The wrapped position contract address
  /// @param _expiration The expiration time of the tranche as a uint256
  /// @return The derived Tranche contract
  function deriveTranche(address _position, uint256 _expiration)
    internal
    view
    virtual
    returns (address)
  {
    bytes32 salt = keccak256(abi.encodePacked(_position, _expiration));
    bytes32 addressBytes = keccak256(
      abi.encodePacked(bytes1(0xff), trancheFactory, salt, trancheBytecodeHash)
    );
    return address(uint160(uint256(addressBytes)));
  }

  struct PoolSpec {
    address underlyingAsset;
    address trancheAddress;
    address tranchePosition;
    address trancheUnderlying;
    address poolUnderlying;
    address poolVaultAddress;
    uint256 poolExpiry;
    bytes32 poolId;
  }

  function checkFunction(
    address contractAddress,
    string memory signature,
    string memory errorMsg
  ) internal returns (bytes memory returnData) {
    (bool operationSuccess, bytes memory data) = contractAddress.call{
      value: 0
    }(abi.encodeWithSignature(signature));
    require(operationSuccess, errorMsg);
    returnData = data;
  }

  function checkAndStorePoolSpecification(
    address wrappedPositionAddress,
    uint256 expiry,
    address poolAddress
  ) internal {
    PoolSpec memory poolSpec;
    IWrappedPosition wrappedPosition = IWrappedPosition(wrappedPositionAddress);
    // this underlying asset should be the real asset i.e. DAI stablecoin etc
    poolSpec.underlyingAsset = address(wrappedPosition.token());
    // this should be the address of the Element tranche for the asset/expiry pair
    poolSpec.trancheAddress = deriveTranche(wrappedPositionAddress, expiry);

    // get the wrapped position held in the tranche to cross check against that provided
    bytes memory returnData = checkFunction(
      poolSpec.trancheAddress,
      "position()",
      "ElementBridge: TRANCHE_POSITION_FAILED"
    );
    poolSpec.tranchePosition = abi.decode(returnData, (address));
    require(
      poolSpec.tranchePosition == wrappedPositionAddress,
      "ElementBridge: TRANCHE_POSITION_MISMATCH"
    );

    // get the underlying held in the tranche to cross check against that provided
    returnData = checkFunction(
      poolSpec.trancheAddress,
      "underlying()",
      "ElementBridge: TRANCHE_UNDERLYING_FAILED"
    );
    poolSpec.trancheUnderlying = abi.decode(returnData, (address));
    require(
      poolSpec.trancheUnderlying == poolSpec.underlyingAsset,
      "ElementBridge: TRANCHE_UNDERLYING_MISMATCH"
    );

    // get the pool underlying to cross check against that provided
    returnData = checkFunction(
      poolAddress,
      "underlying()",
      "ElementBridge: POOL_UNDERLYING_FAILED"
    );
    poolSpec.poolUnderlying = abi.decode(returnData, (address));
    require(
      poolSpec.poolUnderlying == poolSpec.underlyingAsset,
      "ElementBridge: POOL_UNDERLYING_MISMATCH"
    );

    // get the pool expiry to cross check against that provided
    returnData = checkFunction(
      poolAddress,
      "expiration()",
      "ElementBridge: POOL_EXPIRATION_FAILED"
    );
    poolSpec.poolExpiry = abi.decode(returnData, (uint256));
    require(
      poolSpec.poolExpiry == expiry,
      "ElementBridge: POOL_EXPIRY_MISMATCH"
    );

    // get the vault associated with the pool and the pool id
    returnData = checkFunction(
      poolAddress,
      "getVault()",
      "ElementBridge: POOL_VAULT_FAILED"
    );
    poolSpec.poolVaultAddress = abi.decode(returnData, (address));

    returnData = checkFunction(
      poolAddress,
      "getPoolId()",
      "ElementBridge: POOL_ID_FAILED"
    );
    poolSpec.poolId = abi.decode(returnData, (bytes32));

    //verify that the vault address is equal to our balancer address
    require(
      poolSpec.poolVaultAddress == balancerAddress,
      "ElementBridge: VAULT_ADDRESS_VERIFICATION_FAILED"
    );

    uint256 assetExpiryHash = hashAssetAndExpiry(
      poolSpec.underlyingAsset,
      expiry
    );
    pools[assetExpiryHash] = Pool(
      poolSpec.trancheAddress,
      poolAddress,
      poolSpec.poolId
    );
  }

  function hashAssetAndExpiry(address asset, uint256 expiry)
    internal
    pure
    returns (uint256)
  {
    return uint256(keccak256(abi.encodePacked(asset, expiry)));
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

    require(
      interactions[interactionNonce].expiry == 0,
      "ElementBridge: INTERACTION_ALREADY_EXISTS"
    );

    // check expired

    // ### ASYNC BRIDGE LOGIC

    isAsync = true;

    // outputValueA and outputValueB are already initialised as 0 so no need to set.
    // 1. If there are multiple Element pools for the input asset, the DBC should use the value in the auxData to pick the correct pool expiry.

    // auxData should be a unix timestamp (seconds since 01 Jan 1970)
    Pool storage pool = pools[
      hashAssetAndExpiry(inputAssetA.erc20Address, auxData)
    ];
    require(pool.trancheAddress != address(0), "ElementBridge: POOL_NOT_FOUND");
    // 2. Will purchase totalInputValue principal tokens via the Element AMM with the given input asset ERC20

    // Does Balancer require us to approve the tokens being swapped?
    // TODO doesn't work for ETH ???
    // Should we minus a fee here for finalising the bridge at a later date ???

    ERC20(inputAssetA.erc20Address).approve(
      address(balancerAddress),
      totalInputValue
    );

    uint256 principalTokensAmount = IVault(balancerAddress).swap(
      IVault.SingleSwap({
        poolId: pool.poolId,
        kind: IVault.SwapKind.GIVEN_IN,
        assetIn: IAsset(inputAssetA.erc20Address),
        assetOut: IAsset(pool.trancheAddress),
        amount: totalInputValue,
        userData: "0x00"
      }),
      IVault.FundManagement({
        sender: address(this), // the bridge has already received the tokens from the rollup so it owns totalInputValue of inputAssetA
        fromInternalBalance: false,
        recipient: payable(address(this)),
        toInternalBalance: false
      }),
      0, // TODO use the auxData to set this, in the short term allow infinite slippage.
      block.timestamp
    );
    // 3. Record the amount of purchased principal tokens against the interaction nonce for this interaction.
    // 4. Record the maturity date against the interaction nonce so this async transaction can be finalised at a later date
    interactions[interactionNonce] = Interaction(
      pool.trancheAddress,
      auxData,
      principalTokensAmount,
      false
    );
  }

  function canFinalise(uint256 interactionNonce)
    external
    view
    override
    returns (bool)
  {
    Interaction storage interaction = interactions[interactionNonce];
    require(interaction.expiry != 0, "ElementBridge: UNKNOWN_NONCE");
    return interaction.expiry <= block.timestamp && !interaction.finalised;
  }

  function finalise(
    AztecTypes.AztecAsset calldata inputAssetA,
    AztecTypes.AztecAsset calldata inputAssetB,
    AztecTypes.AztecAsset calldata outputAssetA,
    AztecTypes.AztecAsset calldata outputAssetB,
    uint256 interactionNonce,
    uint64 auxData
  ) external payable returns (uint256 outputValueA, uint256 outputValueB) {
    Interaction storage interaction = interactions[interactionNonce];
    require(interaction.expiry != 0, "ElementBridge: UNKNOWN_NONCE");
    require(
      interaction.expiry <= block.timestamp,
      "ElementBridge: TERM_NOT_REACHED"
    );
    require(!interaction.finalised, "ElementBridge: ALREADY_FINALISED");

    outputValueA = ITranche(interaction.trancheAddress).withdrawPrincipal(
      interaction.quantityPT,
      address(this)
    );
    // 1. Call RollupContract.processAsyncDefiInteraction(interactionNonce) with an EOA

    // 2. Incentivise a miner /keeper to call RollupContract.processAsyncDefiInteraction(interactionNonce)

    // 3. Check and call RollupContract.processAsyncDefiInteraction(interactionNonce) in convert.

    // In an asnyc defi interaction, the rollup has to call transferFrom() on the token. This is so a bridge can finanlise another bridge.
    // Therefore to transfer to the rollup, we just need to approve outputValueA for spending by the rollup.
    ERC20(outputAssetA.erc20Address).approve(rollupProcessor, outputValueA);
    interaction.finalised = true;
  }
}
