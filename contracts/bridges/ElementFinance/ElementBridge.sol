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
import { IRollupProcessor } from "../../interfaces/IRollupProcessor.sol";

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
  ) {
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

  function checkContractCall(
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

    bytes memory returnData = checkContractCall(
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
    returnData = checkContractCall(
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
    returnData = checkContractCall(
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
    returnData = checkContractCall(
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
    returnData = checkContractCall(
      poolAddress,
      "getVault()",
      "ElementBridge: POOL_VAULT_FAILED"
    );
    poolSpec.poolVaultAddress = abi.decode(returnData, (address));

    returnData = checkContractCall(
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
    AztecTypes.AztecAsset memory,
    AztecTypes.AztecAsset memory outputAssetA,
    AztecTypes.AztecAsset memory,
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

    isAsync = true;
    Pool storage pool = pools[
      hashAssetAndExpiry(inputAssetA.erc20Address, auxData)
    ];
    require(pool.trancheAddress != address(0), "ElementBridge: POOL_NOT_FOUND");

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

    addNonceAndExpiry(interactionNonce, auxData);
    (bool expiryAvailable, uint64 expiry, uint256 nonce) = checkNextExpiry();
    if (expiryAvailable) {
      IRollupProcessor(rollupProcessor).processAsyncDeFiInteraction(nonce);
    }
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
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata outputAssetA,
    AztecTypes.AztecAsset calldata,
    uint256 interactionNonce,
    uint64
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

    // Check and call RollupContract.processAsyncDefiInteraction(interactionNonce) in convert.

    // In an asnyc defi interaction, the rollup has to call transferFrom() on the token. This is so a bridge can finanlise another bridge.
    // Therefore to transfer to the rollup, we just need to approve outputValueA for spending by the rollup.
    ERC20(outputAssetA.erc20Address).approve(rollupProcessor, outputValueA);

    interaction.finalised = true;
    popInteraction(interaction, interactionNonce);
  }

  uint64[] heap;
  mapping(uint64 => uint256[]) expiryToNonce;

  function addNonceAndExpiry(uint256 nonce, uint64 expiry) internal {
    // get the set of nonces already against this expiry
    uint256[] storage nonces = expiryToNonce[expiry];
    nonces.push(nonce);
    console.log("Added nonce %s to expiry %s", nonce, expiry);
    // is this the first time this expiry has been requested?
    // if so then add it to our expiry heap
    if (nonces.length == 1) {
      addToHeap(expiry);
    }
  }

  function siftUp(uint256 index) internal {
    while (index > 0) {
      uint256 parentIndex = index / 2;
      if (heap[parentIndex] <= heap[index]) {
        break;
      }
      uint64 temp = heap[index];
      heap[index] = heap[parentIndex]; // update
      heap[parentIndex] = temp; // update
      index = index / 2;
    }
  }

  function addToHeap(uint64 expiry) internal {
    // standard min-heap insertion
    // push to the end of the heap and sift up.
    // there is a high probability that the expiry being added will remain where it is
    // so this operation will end up being O(1)
    heap.push(expiry); // write
    uint256 index = heap.length - 1;

    // assuming 5k gas per update, this loop will use ~10k gas per iteration plus the logic
    // if we add in 100k gas for variable heap updates, we can have 1024 active different expiries
    // TODO test this

    siftUp(index);
    console.log("Added expiry %s to heap", expiry);
    printHeap();
  }

  function popFromHeap() internal {
    // if the heap is empty then nothing to do
    if (heap.length == 0) {
      return;
    }
    // slightly modified algorithm for popping from min-heap
    // writes to storage are expensive so we want to do as few as possible
    // read the value in the last position and shrink the array by 1
    uint64 last = heap[heap.length - 1];
    heap.pop();
    // now sift down but no need to swap parent and child nodes
    // we just write the child value into the parent each time
    // then once we no longer have any smaller children, we write the 'last' value into place
    // requires a total of O(logN) updates
    uint256 index = 0;
    while (index < heap.length) {
      // get the indices of the child values
      uint256 leftChildIndex = (index * 2) + 1;
      uint256 rightChildIndex = leftChildIndex + 1;
      uint256 swapIndex = index;
      uint64 smallestValue = last;

      // identify the smallest child, first check the left
      if (
        leftChildIndex < heap.length && heap[leftChildIndex] < smallestValue
      ) {
        swapIndex = leftChildIndex;
        smallestValue = heap[leftChildIndex];
      }
      // then check the right
      if (
        rightChildIndex < heap.length && heap[rightChildIndex] < smallestValue
      ) {
        swapIndex = rightChildIndex;
      }
      // if neither child was smaller then nothing more to do
      if (swapIndex == index) {
        heap[index] = smallestValue;
        break;
      }
      // swap with the smallest child
      heap[index] = heap[swapIndex];
      index = swapIndex;
    }
    console.log("Popped heap");
    printHeap();
  }

  function printHeap() internal {
    uint256 index = 0;
    while (index < heap.length) {
      console.log("Heap at index %s: %s", index, heap[index]);
      index++;
    }
  }

  function popInteraction(
    Interaction storage interaction,
    uint256 interactionNonce
  ) internal {
    uint256[] storage nonces = expiryToNonce[interaction.expiry];
    if (nonces.length == 0) {
      return;
    }
    uint256 index = nonces.length - 1;
    while (index > 0 && nonces[index] != interactionNonce) {
      --index;
    }
    if (nonces[index] != interactionNonce) {
      return;
    }
    nonces[index] = nonces[nonces.length - 1];
    nonces.pop();

    // if there are no more nonces left for this expiry then remove it from the heap
    if (nonces.length == 0) {
      removeExpiryFromHeap(interaction.expiry);
    }
    console.log("Popped interaction: %s", interactionNonce);
  }

  function removeExpiryFromHeap(uint64 expiry) internal {
    uint256 index = 0;
    while (index < heap.length && heap[index] != expiry) {
      ++index;
    }
    if (index == heap.length) {
      return;
    }
    heap[index] = 0;
    siftUp(index);
    popFromHeap();
  }

  function checkNextExpiry()
    internal
    returns (
      bool expiryAvailable,
      uint64 expiry,
      uint256 nonce
    )
  {
    // do we have any expiries and if so is the earliest expiry now expired
    if (heap.length != 0 && heap[0] <= block.timestamp) {
      // we have some expired interactions
      uint256[] storage nonces = expiryToNonce[heap[0]];
      // it shouldn't be possible for the length of this to be 0 but check just in case
      if (nonces.length == 0) {
        // we should pop the heap as it is clearly has the wrong expiry at the root
        popFromHeap();
      } else {
        // grab the nonce at the end
        nonce = nonces[nonces.length - 1];
        expiryAvailable = true;
        expiry = heap[0];
      }
    }
  }
}
