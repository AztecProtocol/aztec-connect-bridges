# How to contribute

This repo has been built with Foundry. Given the inter-connected nature of building bridges with existing main-net protocols. Foundry / forge offered the best support for debugging, mainnet forking, impersonation and gas profiling. We beleive that it makes sense to test solidity with solidty not with an added complication of Ethers / Typescript.

# Writing a bridge

Developing a bridge is permisionless, simply follow the steps below to get started.

1. Fork this repository
2. All bridges need to be submitted via PR's to this repo, we expect developers to do the following as part of their PR.
3. Write a solidity bridge that interfaces with the protocol you are bridging e.g AAVE
4. Write tests in solidity that use the fork from mainnet code to test the bridge with production values and a range of assets and edge cases.
5. Write an explanation of the flows your bridge supports.
6. Implement the typescript bridge-data.ts class that tells an integrator how to use your bridge.
7. Deploy your bridge! Instructions coming soon.

## Getting started

Clone the repo with:

`git clone git@github.com:AztecProtocol/aztec-connect-bridges.git`

Build the repo with:

```
cd aztec-connect-bridges
yarn setup

```

Copy and rename the following folders to the bridge you are building:

```
src/bridges/example
src/test/example
src/client/example

```

To test run:

```
yarn test --match YourBridge
```

To get a gas report run:

```
yarn test --match YourBridge --gas-report
```

To debug:

```
yarn test --match YourBridge -vvvv
```

## Testing methodolgy

This repo includes an infura key that allows forking from mainnet. We have included some helpers to make testing easier.

In production a bridge is called by a user creating a client side proof via the Aztec Sdk. These transaction proofs are sent to a rollup provider for aggregation. The rollup provider then sends the aggregate rollup proof with the sum of all users proofs for a given bridgeId to your bridge contract.

A bridgeId consists of the below schema. The rollup contract uses this to construct the function parameters to pass into your bridge contract. It calls your bridge with a fixed amount of gas via a `delegateCall` via the `DefiBridgeProxy.sol` contract.

To test a bridge, we have added a `MockRollupProcessor` that simulates a rollup. You can call this in your tests by simply calling `rollupContract.convert()` with the deconstructed bridgeId fields.

In production, the rollup contract will supply `totalInputValue` as the aggregate sum of the input assets, and `interactionNonce` as a globally unique id. For testing you can provide this.

The rollup contract will send `totalInputValue` of `inputAssetA` and `inputAssetB` ahead of the call to convert. In production, the rollup contract has these tokens as they are the users funds. For testing there is a helper to prefund the rollup with sufficient tokens to enable the transfer.

Simply call:

```solidity
  _setTokenBalance(address(dai), address(rollupProcessor), depositAmount);
```

This will set the balance of the rollup to the amount required.

## Sending Tokens Back to the Rollup

The rollup contract expects a bridge to have approved for transfer by the `rollupAddress` the ERC20 tokens that are returned via `outputValueA` or `outputValueB` for a given asset. The DeFiBridgeProxy.sol will attempt to recover by calling `transferFrom(bridgeAddress, rollupAddress, amount)` for these values once `bridge.convert()` or `bridge.finalise()` have executed.

ETH is returned to the rollup from a bridge by calling the payable function with a msg.value `rollupContract.receiveETH(uint256 interactionNonce)`. You must also set the `outputValue` of the corresponding `outputAsset` to be the amount of ETH sent.

This repo supports TypeChain so all typescript bindings will be auto generated and added to the `typechain-types` folder. See the example tests for more info.

### Bridge Id Structure

```
[^1]: Bridge id is a 250-bit concatenation of the following data (starting at the most significant bit position):

| bit position | bit length | definition | description |
| --- | --- | --- | --- |
| 0 | 64 | `auxData` | custom auxiliary data for bridge-specific logic |
| 64 | 32 | `bitConfig` | flags that describe asset types |
| 96 | 32 | `openingNonce` | (optional) reference to a previous defi interaction nonce (used for virtual assets) |
| 128 | 30 |  `outputAssetB` | asset id of 2nd output asset |
| 158 | 30 | `outputAssetA` | asset id of 1st output asset |
| 188 | 30 | `inputAsset` | asset id of 1st input asset |
| 218 | 32 | `bridgeAddressId` | id of bridge smart contract address |


Bit Config Definition
| bit | meaning |
| --- | --- |
| 0   | firstInputAssetVirtual |
| 1   | secondInputAssetVirtual |
| 2   | firstOutputAssetVirtual |
| 3   | secondOutputAssetVirtual |
| 4   | secondInputValid |
| 5   | secondOutputValid |
```

###

# Aztec Connect Background

### What is Aztec?

Aztec is a privacy focussed L2, that enables cheap private interactions with Layer 1 smart contracts and liquidity, via a process called DeFi aggregation. We use advanced zero-knowledge technology "zk-zk rollups" to add privacy and significant gas savings any Layer 1 protocol via Aztec Connect bridges.

#### What is a bridge?

A bridge is a Layer solidity contract deployed on Mainnet that conforms a DeFi protocol to the interface the Aztec rollup expects. This allows the Aztec rollup contract to interact with the DeFi protocol via the bridge.

A bridge contract models any layer 1 DeFi protocol as an asynchronous asset swap. You can specify up to two input assets and two output assets per bridge.

#### How does this work?

Users who have shielded fuassetsnds on Aztec can construct a zero-knowledge proof instructing the Aztec rollup contract to make an external L1 contract call.

Rollup providers batch multiple L2 transaction intents on the Aztec Network together in a rollup. The rollup contract then makes aggregate transaction against L1 DeFi contracts and returns the funds pro-rata to the users on L2.

#### How much does this cost?

Aztec connect transactions can be batched together into one rollup. Each user in the batch pays a base fee to cover the verification of the rollup proof and their share of the L1 DeFi transaction gas cost. A single Aztec Connect transaction requires 3 base fees or aproximatley ~8000 gas.

The user then pays their share of the L1 Defi transaction. The rollup will call a bridge contract with a fixed deterministic amount of gas so the total fee is simple ~8000 gas + BRIDGE_GAS / BATCH_SIZE.

#### What is private?

The source of funds for any Aztec Connect transaction is an Aztec shielded asset. When a user interacts with an Aztec Connect Bridge contract, their identity is kept hidden, but balances set to the bridge are public.

#### Batching

Rollup providers are incentivised to batch any transaction with the same BridgeId. This reduces the cost of the L1 transaction for similar trades. A bridgeId consits of:

## Virtual Assets

Aztec uses the concept of Virtual Assets or Position tokens to represent a share of assets held by a Bridge contract. This is far more gas efficient than minting ERC20 tokens.These are used when the bridge holds an asset that Aztec doesn't support i.e Uniswap Position NFT's or other non-fungible assets.

If the output asset of any interaction is specified as "VIRTUAL", the user will receive encrypted notes on Aztec representing their share of the position, but no Tokens or ETH need to be transfered. The position tokens have an `assetId` that is the `interactionNonce` of the DeFi Bridge call. This is globably unique. Virtual assets can be used to construct complex flows, such as entering or exiting LP positions. i.e one bridge contract can have multiple flows which are triggered using different input assets.

## Aux Input Data

The auxData field can be used to provide data to the bridge contract, such as slippage, tokenIds etc.

#### Bridge Contract Interface

```solidity
// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.6 <0.8.0;
pragma experimental ABIEncoderV2;

import { Types } from "../Types.sol";

interface IDefiBridge {
  /**
   * Input cases:
   * Case1: 1 real input.
   * Case2: 1 virtual asset input.
   * Case3: 1 real 1 virtual input.
   *
   * Output cases:
   * Case1: 1 real
   * Case2: 2 real
   * Case3: 1 real 1 virtual
   * Case4: 1 virtual
   *
   * Example use cases with asset mappings
   * 1 1: Swapping.
   * 1 2: Swapping with incentives (2nd output reward token).
   * 1 3: Borrowing. Lock up collateral, get back loan asset and virtual position asset.
   * 1 4: Opening lending position OR Purchasing NFT. Input real asset, get back virtual asset representing NFT or position.
   * 2 1: Selling NFT. Input the virtual asset, get back a real asset.
   * 2 2: Closing a lending position. Get back original asset and reward asset.
   * 2 3: Claiming fees from an open position.
   * 2 4: Voting on a 1 4 case.
   * 3 1: Repaying a borrow. Return loan plus interest. Get collateral back.
   * 3 2: Repaying a borrow. Return loan plus interest. Get collateral plus reward token. (AAVE)
   * 3 3: Partial loan repayment.
   * 3 4: DAO voting stuff.
   */

  // @dev This function is called from the RollupProcessor.sol contract via the DefiBridgeProxy. It receives the aggreagte sum of all users funds for the input assets.
  // @param AztecAsset inputAssetA a struct detailing the first input asset, this will always be set
  // @param AztecAsset inputAssetB an optional struct detailing the second input asset, this is used for repaying borrows and should be virtual
  // @param AztecAsset outputAssetA a struct detailing the first output asset, this will always be set
  // @param AztecAsset outputAssetB a struct detailing an optional second output asset
  // @param uint256 inputValue, the total amount input, if there are two input assets, equal amounts of both assets will have been input
  // @param uint256 interactionNonce a globally unique identifier for this DeFi interaction. This is used as the assetId if one of the output assets is virtual
  // @param uint64 auxData other data to be passed into the bridge contract (slippage / nftID etc)
  // @return uint256 outputValueA the amount of outputAssetA returned from this interaction, should be 0 if async
  // @return uint256 outputValueB the amount of outputAssetB returned from this interaction, should be 0 if async or bridge only returns 1 asset.
  // @return bool isAsync a flag to toggle if this bridge interaction will return assets at a later date after some third party contract has interacted with it via finalise()
  function convert(
    Types.AztecAsset calldata inputAssetA,
    Types.AztecAsset calldata inputAssetB,
    Types.AztecAsset calldata outputAssetA,
    Types.AztecAsset calldata outputAssetB,
    uint256 inputValue,
    uint256 interactionNonce,
    uint64 auxData
  )
    external
    payable
    returns (
      uint256 outputValueA,
      uint256 outputValueB,
      bool isAsync
    );

  // @dev This function is called from the RollupProcessor.sol contract via the DefiBridgeProxy. It receives the aggreagte sum of all users funds for the input assets.
  // @param AztecAsset inputAssetA a struct detailing the first input asset, this will always be set
  // @param AztecAsset inputAssetB an optional struct detailing the second input asset, this is used for repaying borrows and should be virtual
  // @param AztecAsset outputAssetA a struct detailing the first output asset, this will always be set
  // @param AztecAsset outputAssetB a struct detailing an optional second output asset
  // @param uint256 interactionNonce
  // @param uint64 auxData other data to be passed into the bridge contract (slippage / nftID etc)
  // @return uint256 outputValueA the return value of output asset A
  // @return uint256 outputValueB optional return value of output asset B
  // @dev this function should have a modifier on it to ensure it can only be called by the Rollup Contract
  function finalise(
    Types.AztecAsset calldata inputAssetA,
    Types.AztecAsset calldata inputAssetB,
    Types.AztecAsset calldata outputAssetA,
    Types.AztecAsset calldata outputAssetB,
    uint256 interactionNonce,
    uint64 auxData
  ) external payable returns (uint256 outputValueA, uint256 outputValueB, bool interactionComplete);
}

```

### Async flow explainer

If a Defi Bridge interaction is asynchronous, it must be finalised at a later date once the DeFi interaction has completed.

This is acheived by calling `RollupProcessor.processAsyncDefiInteraction(uint256 interactionNonce)`. This internally will call finalise and ensure the correct amount of tokens have been transferred.

#### convert()

This function is called from the Aztec Rollup Contract via the DeFi Bridge Proxy. Before this function on your bridge contract is called the rollup contract will have sent you ETH or Tokens defined by the input params.

This function should interact with the DeFi protocol e.g Uniswap, and transfer tokens or ETH back to the Aztec Rollup Contract. The Rollup contract will check it received the correct amount.

If the DeFi interaction is ASYNC i.e it does not settle in the same block, the call to convert should return (0,0 true). The contract should record the interaction nonce for any Async position or if virtual assets are returned.

At a later date, this interaction can be finalised by proding the rollup contract to call finalise on the bridge.

#### function finalise()

This function will be called from the Azte Rollup contract. The Aztec rollup contract will check that it received the correct amount of ETH and Tokens specified by the return values, and trigger the settlement step on Aztec.
