 // SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/utils/math/SafeMath.sol";
import { ERC20 } from "@openzeppelin/token/ERC20/ERC20.sol";
import { IVault, IAsset, PoolSpecialization } from "./interfaces/IVault.sol";
import { IPool } from "./interfaces/IPool.sol";
import { ITranche } from "./interfaces/ITranche.sol";
import { IERC20Permit, IERC20 } from "./interfaces/IERC20Permit.sol";
import { IWrappedPosition } from "./interfaces/IWrappedPosition.sol";
import { IRollupProcessor } from "./interfaces/IRollupProcessor.sol";

import { IDefiBridge } from "../../interfaces/IDefiBridge.sol";

import { AztecTypes } from "../../aztec/AztecTypes.sol";

import "../../test/console.sol";

contract ElementBridge is IDefiBridge {
  // capture the minimum info required to recall a deposit
  struct Interaction {
    address trancheAddress;
    uint64 expiry;
    uint256 quantityPT;
    bool finalised;
  }

  // minimum info required to execute a deposit
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

  // cache of all of our Defi interactions. keyed on nonce
  mapping(uint256 => Interaction) public interactions;

  mapping(address => uint64[]) public assetToExpirys;

  // cahce of all pools we are able to interact with
  mapping(uint256 => Pool) public pools;

  // the aztec rollup processor contract
  address public immutable rollupProcessor;

  // the balancer contract
  address private immutable balancerAddress;

  uint64[] private heap;
  uint32[] private expiries;

  mapping(uint64 => uint256[]) private expiryToNonce;

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

  function getAssetExpiries(address asset) public view returns (uint64[] memory assetExpiries) {
     return assetToExpirys[asset];
  }

  // this function allows for the dynamic addition of new asset/expiry combinations as they come online
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

  // function to validate a pool specification
  // do the wrapped position address, the pool address and the expiry cross reference with one another
  function checkAndStorePoolSpecification(
    address wrappedPositionAddress,
    uint256 expiry,
    address poolAddress
  ) internal {
    PoolSpec memory poolSpec;
    IWrappedPosition wrappedPosition = IWrappedPosition(wrappedPositionAddress);
    console.log("WP: total %s", wrappedPosition.token().totalSupply());
    // this underlying asset should be the real asset i.e. DAI stablecoin etc
    poolSpec.underlyingAsset = address(wrappedPosition.token());
    // this should be the address of the Element tranche for the asset/expiry pair
    poolSpec.trancheAddress = deriveTranche(wrappedPositionAddress, expiry);
    // get the wrapped position held in the tranche to cross check against that provided
    ITranche tranche = ITranche(poolSpec.trancheAddress);
    poolSpec.tranchePosition = address(tranche.position());
    require(
      poolSpec.tranchePosition == wrappedPositionAddress,
      "ElementBridge: TRANCHE_POSITION_MISMATCH"
    );
    // get the underlying held in the tranche to cross check against that provided
    poolSpec.trancheUnderlying = address(tranche.underlying());
    require(
      poolSpec.trancheUnderlying == poolSpec.underlyingAsset,
      "ElementBridge: TRANCHE_UNDERLYING_MISMATCH"
    );
    // get the pool underlying to cross check against that provided
    IPool pool = IPool(poolAddress);
    poolSpec.poolUnderlying = address(pool.underlying());
    require(
      poolSpec.poolUnderlying == poolSpec.underlyingAsset,
      "ElementBridge: POOL_UNDERLYING_MISMATCH"
    );
    // get the pool expiry to cross check against that provided
    poolSpec.poolExpiry = pool.expiration();
    require(
      poolSpec.poolExpiry == expiry,
      "ElementBridge: POOL_EXPIRY_MISMATCH"
    );
    // get the vault associated with the pool and the pool id
    poolSpec.poolVaultAddress = address(pool.getVault());

    poolSpec.poolId = pool.getPoolId();

    //verify that the vault address is equal to our balancer address
    require(
      poolSpec.poolVaultAddress == balancerAddress,
      "ElementBridge: VAULT_ADDRESS_VERIFICATION_FAILED"
    );

    // retrieve the pool address for the given pool id from balancer
    // then test it against that given to us
    IVault balancerVault = IVault(balancerAddress);
    (address balancersPoolAddress, PoolSpecialization balancersPoolSpec) = balancerVault.getPool(poolSpec.poolId);
    require(poolAddress == balancersPoolAddress, "ElementBridge: VAULT_ADDRESS_MISMATCH");

    // TODO: Further pool validation

    // we store the pool information against a hash of the asset and expiry
    uint256 assetExpiryHash = hashAssetAndExpiry(
      poolSpec.underlyingAsset,
      expiry
    );

    pools[assetExpiryHash] = Pool(
      poolSpec.trancheAddress,
      poolAddress,
      poolSpec.poolId
    );

    uint64[] storage expiriesForAsset = assetToExpirys[poolSpec.underlyingAsset];
    expiriesForAsset.push(uint64(poolSpec.poolExpiry));

  }

  function hashAssetAndExpiry(address asset, uint256 expiry)
    public
    pure
    returns (uint256)
  {
    return uint256(keccak256(abi.encodePacked(asset, expiry)));
  }

  // convert the input asset to the output asset
  // serves as the 'on ramp' to the interaction
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
    // operation is asynchronous
    isAsync = true;
    // retrieve the appropriate pool for this interaction and verify that it exists
    Pool storage pool = pools[
      hashAssetAndExpiry(inputAssetA.erc20Address, auxData)
    ];
    require(pool.trancheAddress != address(0), "ElementBridge: POOL_NOT_FOUND");
    // CHECK INPUT ASSET != ETH
    // SHOULD WE CONVERT ETH -> WETH

    // approve the transfer of tokens to the balancer address
    ERC20(inputAssetA.erc20Address).approve(
      address(balancerAddress),
      totalInputValue
    );
    // execute the swap on balancer
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
      totalInputValue, // discuss with ELement on the likely slippage for a large trade e.g $1M Dai
      block.timestamp
    );
    console.log("Received %s tokens for input of %s", principalTokensAmount, totalInputValue);
    // store the tranche that underpins our interaction, the expiry and the number of received tokens against the nonce
    interactions[interactionNonce] = Interaction(
      pool.trancheAddress,
      auxData,
      principalTokensAmount,
      false
    );
    // add the nonce and expiry to our expiry heap
    addNonceAndExpiry(interactionNonce, auxData);
    // check the heap to see if we can finalise an expired transaction
    (bool expiryAvailable, uint64 expiry, uint256 nonce) = checkNextArrayExpiry();//checkNextExpiry();
    if (expiryAvailable) {
      // another position is available for finalising, inform the rollup contract
      IRollupProcessor(rollupProcessor).processAsyncDeFiInteraction(nonce);
    }
  }

  // serves as the 'off ramp' for the transaction
  // converts the principal tokens back to the underlying asset
  function finalise(
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata,
    AztecTypes.AztecAsset calldata outputAssetA,
    AztecTypes.AztecAsset calldata,
    uint256 interactionNonce,
    uint64
  ) external payable returns (uint256 outputValueA, uint256 outputValueB, bool interactionComplete) {

    require(msg.sender == rollupProcessor, "ElementBridge: INVALID_CALLER");
    // retrieve the interaction and verify it's ready for finalising
    Interaction storage interaction = interactions[interactionNonce];
    require(interaction.expiry != 0, "ElementBridge: UNKNOWN_NONCE");
    require(
      interaction.expiry <= block.timestamp,
      "ElementBridge: BRIDGE_NOT_READY"
    );
    require(!interaction.finalised, "ElementBridge: ALREADY_FINALISED");

    // convert the tokens back to underlying using the tranche
    console.log("Withdrawing %s principal tokens", interaction.quantityPT);
    console.log("Total supply %s", ITranche(interaction.trancheAddress).totalSupply());
    outputValueA = ITranche(interaction.trancheAddress).withdrawPrincipal(
      interaction.quantityPT,
      address(this)
    );
    // approve the transfer of funds back to the rollup contract
    ERC20(outputAssetA.erc20Address).approve(rollupProcessor, outputValueA);

    // interaction is completed. clean up the expiry heap
    interaction.finalised = true;
    popInteraction(interaction, interactionNonce);
    console.log("Successfully finalised interaction: ", interactionNonce);
    interactionComplete = true;
  }

  // add an interaction nonce and expiry to the expiry heap
  function addNonceAndExpiry(uint256 nonce, uint64 expiry) internal {
    // get the set of nonces already against this expiry
    uint256[] storage nonces = expiryToNonce[expiry];
    nonces.push(nonce);
    // is this the first time this expiry has been requested?
    // if so then add it to our expiry heap
    if (nonces.length == 1) {
      //addToHeap(expiry);
      addToArray(expiry);
    }
  }

  // move an expiry up through the heap to the correct position
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

  function addToArray(uint64 expiry) internal {
    expiries.push(uint32(expiry));
    console.log("Added expiry %s to array", expiry);
    printArray();
  }

  // add a new expiry to the heap
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
    printHeap();
  }

  // remove the root expiry from the heap
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
  }

  function printHeap() internal {
    uint256 index = 0;
    while (index < heap.length) {
      index++;
    }
  }

  function printArray() internal {
    uint256 index = 0;
    while (index < expiries.length) {
      index++;
    }
  }

  // clean an interaction from the heap
  // optimised to remove the last interaction for the earliest expiry but will work in all cases (just at the expense of gas)
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
    if (index != nonces.length - 1) {
      nonces[index] = nonces[nonces.length - 1];
    }
    nonces.pop();

    // if there are no more nonces left for this expiry then remove it from the heap
    if (nonces.length == 0) {
      //removeExpiryFromHeap(interaction.expiry);
      removeExpiryFromArray(interaction.expiry);
    }
    console.log("Popped interaction: %s", interactionNonce);
  }

  // will remove an expiry from the min-heap
  function removeExpiryFromHeap(uint64 expiry) internal {
    uint256 index = 0;
    while (index < heap.length && heap[index] != expiry) {
      ++index;
    }
    if (index == heap.length) {
      return;
    }
    if (index != 0) {
      heap[index] = 0;
      siftUp(index);
    }
    popFromHeap();
  }

  function removeExpiryFromArray(uint64 expiry) internal {
    uint256 index = 0;
    while(index < expiries.length && expiries[index] != expiry) {
      ++index;
    }
    if (index < expiries.length) {
      expiries[index] = expiries[expiries.length - 1];
      expiries.pop();
    }
    console.log("Removed expiry %s from array", expiry);
    printArray();
  }

  function findSmallestExpiryIndex() internal returns (uint256 smallestIndex) {
    uint32 smallest = expiries[0];
    uint256 smallestIndex = 0;
    uint256 index = 1;
    while (index < expiries.length) {
      if (expiries[index] < smallest) {
        smallest = expiries[index];
        smallestIndex = index;
      }
      ++index;
    }
  }

  function checkNextArrayExpiry()
    internal
    returns (
      bool expiryAvailable,
      uint64 expiry,
      uint256 nonce
    ) {
    // do we have any expiries and if so is the earliest expiry now expired
    if (expiries.length != 0) {
      uint256 smallestIndex = findSmallestExpiryIndex();
      uint64 smallestExpiry = expiries[smallestIndex];
      if (smallestExpiry <= block.timestamp) {
        uint256[] storage nonces = expiryToNonce[smallestExpiry];
        // it shouldn't be possible for the length of this to be 0 but check just in case
        if (nonces.length == 0) {
          // we should pop the heap as it is clearly has the wrong expiry at the root
          removeExpiryFromArray(smallestExpiry);
        } else {
          // grab the nonce at the end
          nonce = nonces[nonces.length - 1];
          expiryAvailable = true;
          expiry = smallestExpiry;
        }
      }
    }
  }

  // fast lookup to determine if we have an interaction that can be finalised
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
