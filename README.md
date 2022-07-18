# Aztec Connect Bridges

[![CircleCI](https://circleci.com/gh/AztecProtocol/aztec-connect-bridges/tree/master.svg?style=shield)](https://circleci.com/gh/AztecProtocol/aztec-connect-bridges/tree/master)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](code_of_conduct.md)

## How to contribute

This repo has been built with Foundry.
Given the interconnected nature of Aztec Connect Bridges with existing mainnet protocols, we decided Foundry / Forge offered the best support for testing.
This repo should make debugging, mainnet-forking, impersonation and gas profiling simple.
It makes sense to test Solidity contracts with Solidity, not with the added complication of Ethers / Typescript.

## Writing a bridge

Developing a bridge is simple.
It is done entirely in Solidity and no knowledge of cryptography underpinning Aztec Connect is required.
Users of your bridge will get the full benefits of ironclad privacy and 10-30x gas savings.

> Note: Currently adding a new bridge or asset to Aztec Connect is permissioned and requires our approval.
> Once Aztec Connect leaves beta this won't be the case anymore and developing a bridge will become completely permissionless.

To get started follow the steps bellow:

1. Fork / clone this repository:

   `git clone git@github.com:AztecProtocol/aztec-connect-bridges.git`

2. Install dependencies and build the repo:
   ```
      cd aztec-connect-bridges
      yarn
      git submodule update --init
      yarn setup
   ```
3. Copy and rename the following folders (e.g. rename example to uniswap):

   ```
   src/bridges/example
   src/test/example
   src/client/example
   ```

4. Implement the bridges and tests. See the [example bridge](https://github.com/AztecProtocol/aztec-connect-bridges/blob/master/src/bridges/example/ExampleBridge.sol) and [example bridge tests](https://github.com/AztecProtocol/aztec-connect-bridges/tree/master/src/test/bridges/example) for more details. For a more complex example check out other bridges in this repository.

5. Debug your bridge:

   `forge test --match-contract YourBridge -vvv`

6. Gas-profile your contract:

   `forge test --match-contract YourBridge --gas-report`

All bridges need to be submitted via PRs to this repo.
To receive a grant payment we expect the following work to be done:

1. A solidity bridge that interfaces with the protocol you are bridging to (e.g AAVE),
2. tests in Solidity that test the bridge with production values and the deployed protocol that is currently on mainnet (you should test a range of assets, edge cases and use [Forge's fuzzing abilities](https://book.getfoundry.sh/forge/fuzz-testing.html)),
3. implementation of the Typescript `bridge-data.ts` class that tells a frontend developer how to use your bridge.
4. an explanation of the flows your bridge supports should be included as `spec.md`,
5. [NatSpec](https://docs.soliditylang.org/en/develop/natspec-format.html) documentation of all the functions in all the contracts which are to be deployed on mainnet.

Before submitting a PR for a review make sure that the following is true:

1. All the tests you wrote pass (`forge test --match-contract TestName`),
2. there are no linting errors (`yarn lint`),
3. your branch has been rebased against the head of the `master` branch (**_not merged_**, if you are not sure how to rebase check out [this article](https://blog.verslu.is/git/git-rebase/)),
4. the diff contains only changes related to the PR description,
5. NatSpec documentation has already been written.

## Deployed Bridge Info

| Bridge (link to contract)                                                                   | Id (aka `addressId` in the SDK) | InputAssetA (AssetId)                                                                             | InputAssetB (AssetId) | OutputAssetA (AssetId)                                     | OutputAssetB (AssetId) | auxData                                       | async | Description                                                                                                   |
| ------------------------------------------------------------------------------------------- | ------------------------------- | ------------------------------------------------------------------------------------------------- | --------------------- | ---------------------------------------------------------- | ---------------------- | --------------------------------------------- | ----- | ------------------------------------------------------------------------------------------------------------- |
| [Element](https://etherscan.io/address/0xaeD181779A8AAbD8Ce996949853FEA442C2CDB47)          | 1                               | DAI (1)                                                                                           | Not used              | DAI (1)                                                    | Not used               | The tranche expiry value for the interaction. | Yes   | Smart contract responsible for depositing, managing and redeeming Defi interactions with the Element protocol |
| [LidoBridge](https://etherscan.io/address/0x381abF150B53cc699f0dBBBEF3C5c0D1fA4B3Efd)       | 2                               | ETH (0) or wstETH (2)                                                                             | Not used              | wstETH (2) or ETH (0)                                      | Not used               | Not used                                      | No    | Deposit Eth and get wstETH from Lido, or deposit wstETH and get ETH from a Curve swap.                        |
| [AceOfZkBridge](https://etherscan.io/address/0x0eb7F9464060289fE4FDDFDe2258f518c6347a70)    | 4                               | [Ace of ZK NFT](https://opensea.io/assets/ethereum/0xe56b526e532804054411a470c49715c531cfd485/16) | Not used              | Not used                                                   | Not used               |                                               | No    | A bridge to send the Ace of ZK to the rollup processor contract.                                              |
| [CurveStEthBridge](https://etherscan.io/address/0x0031130c56162e00A7e9C01eE4147b11cbac8776) | 5                               | ETH (0) or wstETH (2)                                                                             | Not used              | wsthETH (2) or ETH (0) - will be opposite of `inputAssetA` | Not used               | Not used                                      | No    | A DeFiBridge for trading between Eth and wstEth using curve and the stEth wrapper.                            |

You can find more information about setting up connections to bridge contracts with the SDK on the [Ethereum Interactions](https://docs.aztec.network/sdk/usage/ethereum-interaction) page of the docs.

## Testing methodology

This repo includes an Infura key that allows forking from mainnet.
We have included helpers to make testing easier (see [example bridge tests](https://github.com/AztecProtocol/aztec-connect-bridges/tree/master/src/test/bridges/example)).

In production a bridge is called by a user creating a client side proof via the Aztec SDK.
These transaction proofs are sent to a rollup provider for aggregation.
The rollup provider then sends the aggregate rollup proof with the sum of all users' proofs for a given `bridgeCallData` to your bridge contract.

A `bridgeCallData` uniquely defines the expected inputs/outputs of a DeFi interaction.
It is a `uint256` that represents a bit-string containing multiple fields.
When unpacked its data is used to create a BridgeData struct in the rollup processor contract.

Structure of the bit-string is as follows (starting at the least significant bit):

| bit position | bit length | definition        | description                                     |
| ------------ | ---------- | ----------------- | ----------------------------------------------- |
| 0            | 32         | `bridgeAddressId` | id of bridge smart contract address             |
| 32           | 30         | `inputAssetA`     | asset id of 1st input asset                     |
| 62           | 30         | `inputAssetB`     | asset id of 1st input asset                     |
| 92           | 30         | `outputAssetA`    | asset id of 1st output asset                    |
| 122          | 30         | `outputAssetB`    | asset id of 2nd output asset                    |
| 152          | 32         | `bitConfig`       | flags that describe asset types                 |
| 184          | 64         | `auxData`         | custom auxiliary data for bridge-specific logic |

Bit Config Definition:

| bit | meaning           |
| --- | ----------------- |
| 0   | secondInputInUse  |
| 1   | secondOutputInUse |

> Note 1: Last 8 bits of `bridgeCallData` bit-string are wasted because the circuits don't support values of full 256 bits (248 is the largest multiple of 8 that we can use).

> Note 2: `bitConfig` is 32 bits large even though we only use 2 bits because we need it to be future proofed (e.g. we might add NFT support, and we would need new bit flag for that).

The rollup contract uses this to construct the function parameters to pass into your bridge contract (via `convert(...)` function).
It calls your bridge with a fixed amount of gas via a `delegateCall` via the `DefiBridgeProxy.sol` contract.

We decided to have 2 separate approaches of bridge testing:

1. In the first one it is expected that you call convert function directly on the bridge contract.
   This allows for simple debugging because execution traces are simple.
   Disadvantage of this approach is that you have take care of transferring tokens to and from the bridge (this is handle by the DefiBridgeProxy contract in the production environment).
   This type of test can be considered to be a unit test and an example of such a test is [here](https://github.com/AztecProtocol/aztec-connect-bridges/blob/master/src/test/bridges/example/ExampleUnit.t.sol).

2. In the second approach we construct a `bridgeCallData`, we mock proof data and verifier's response and we pass this data directly to the RollupProcessor's `processRollup(...)` function.
   The purpose of this test is to test the bridge in an environment that is as close to the final deployment as possible without spinning up all the rollup infrastructure (sequencer, proof generator etc.).
   This test can be considered an end-to-end test of the bridge and an example of such a test is [here](https://github.com/AztecProtocol/aztec-connect-bridges/blob/master/src/test/bridges/example/ExampleE2E.t.sol).

In production, the rollup contract will supply `_inputValue` of both input assets and use the `_interactionNonce` as a globally unique ID.
For testing, you may provide this value.

The rollup contract will send `_inputValue` of `_inputAssetA` and `_inputAssetB` ahead of the call to convert.
In production, the rollup contract already has these tokens as they are the users' funds.
For testing use the `deal` method from the [forge-std](https://github.com/foundry-rs/forge-std)'s `Test` class (see [Example.t.sol](https://github.com/AztecProtocol/aztec-connect-bridges/blob/master/src/test/example/Example.t.sol) for details).
This method prefunds the rollup with sufficient tokens to enable the transfer.

After extending the `Test` class simply call:

```solidity
  deal(address(dai), address(rollupProcessor), amount);
```

This will set the balance of the rollup to the amount required.

## Sending Tokens Back to the Rollup

The rollup contract expects a bridge to have approved for transfer by the `rollupAddress` the ERC20 tokens that are returned via `outputValueA` or `outputValueB` for a given asset.
The `DeFiBridgeProxy` will attempt to recover the tokens by calling `transferFrom(bridgeAddress, rollupAddress, amount)` for these values once `bridge.convert()` or `bridge.finalise()` have executed (in production and in end-to-end tests).
In unit tests it is expected that you transfer these tokens on your own.

ETH is returned to the rollup from a bridge by calling the payable function with a `msg.value` `rollupContract.receiveETH(uint256 interactionNonce)`.
You must also set the `outputValue` of the corresponding `outputAsset` (A or B) to be the amount of ETH sent.

This repo supports TypeChain so all Typescript bindings will be auto generated and added to the `typechain-types` folder.

### bridge-data.ts

This is a Typescript class designed to help a developer on the frontend use your bridge. There are 4 variants of the class:

```
BridgeData
AsyncBridgeData
YieldBridgeData
AsyncYieldBridgeData
```

You should pick the class that describes the functionality of your bridge and implement the functions to fetch data from your bridge / L1.

## Aztec Connect Background

You can also find more information on the [Aztec docs site](https://docs.aztec.network).

### What is Aztec?

Aztec is a privacy focussed L2, that enables cheap private interactions with Layer 1 smart contracts and liquidity, via a process called DeFi Aggregation.
We use advanced zero-knowledge technology "zk-zk rollups" to add privacy and significant gas savings any Layer 1 protocol via Aztec Connect bridges.

#### What is a bridge?

A bridge is a Layer 1 Solidity contract deployed on mainnet that conforms a DeFi protocol to the interface the Aztec rollup expects.
This allows the Aztec rollup contract to interact with the DeFi protocol via the bridge.

A bridge contract models any Layer 1 DeFi protocol as an asynchronous asset swap. You can specify up to two input assets and two output assets per bridge.

#### How does this work?

Users who have shielded assets on Aztec can construct a zero-knowledge proof instructing the Aztec rollup contract to make an external L1 contract call.

Rollup providers batch multiple L2 transaction intents on the Aztec Network together in a rollup.
The rollup contract then makes aggregate transaction against L1 DeFi contracts and returns the funds pro-rata to the users on L2.

#### How much does this cost?

Aztec connect transactions can be batched together into one rollup.
Each user in the batch pays a base fee to cover the verification of the rollup proof and their share of the L1 DeFi transaction gas cost.
A single Aztec Connect transaction requires 3 base fees or approximately ~8000 gas.

The user then pays their share of the L1 DeFi transaction.
The rollup will call a bridge contract with a fixed deterministic amount of gas so the total fee is simple ~8000 gas + BRIDGE_GAS / BATCH_SIZE.

#### What is private?

The source of funds for any Aztec Connect transaction is an Aztec shielded asset.
When a user interacts with an Aztec Connect Bridge contract, their identity is kept hidden, but balances sent to the bridge are public.

## Virtual Assets

Aztec uses the concept of Virtual Assets or Position tokens to represent a share of assets held by a Bridge contract.
This is far more gas efficient than minting ERC20 tokens.
These are used when the bridge holds an asset that Aztec doesn't support (e.g. Uniswap Position NFT's or other non-fungible assets).

If the output asset of any interaction is specified as "VIRTUAL", the user will receive encrypted notes on Aztec representing their share of the position, but no tokens or ETH need to be transferred.
The position tokens have an `assetId` that is the `interactionNonce` of the DeFi Bridge call.
This is globally unique.
Virtual assets can be used to construct complex flows, such as entering or exiting LP positions (e.g. one bridge contract can have multiple flows which are triggered using different input assets).

## Aux Input Data

The `_auxData` field can be used to provide data to the bridge contract, such as slippage, tokenIds etc.

#### Bridge Contract Interface

```solidity
// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Aztec
pragma solidity >=0.8.4;

import { AztecTypes } from "../libraries/AztecTypes.sol";

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

  // @dev This function is called from the RollupProcessor.sol contract via the DefiBridgeProxy. It receives the aggregate sum of all users funds for the input assets.
  // @param AztecAsset _inputAssetA a struct detailing the first input asset, this will always be set
  // @param AztecAsset _inputAssetB an optional struct detailing the second input asset, this is used for repaying borrows and should be virtual
  // @param AztecAsset _outputAssetA a struct detailing the first output asset, this will always be set
  // @param AztecAsset _outputAssetB a struct detailing an optional second output asset
  // @param uint256 _inputValue, the total amount input, if there are two input assets, equal amounts of both assets will have been input
  // @param uint256 _interactionNonce a globally unique identifier for this DeFi interaction. This is used as the assetId if one of the output assets is virtual
  // @param uint64 _auxData other data to be passed into the bridge contract (slippage / nftID etc)
  // @return uint256 outputValueA the amount of outputAssetA returned from this interaction, should be 0 if async
  // @return uint256 outputValueB the amount of outputAssetB returned from this interaction, should be 0 if async or bridge only returns 1 asset.
  // @return bool isAsync a flag to toggle if this bridge interaction will return assets at a later date after some third party contract has interacted with it via finalise()
  function convert(
    AztecTypes.AztecAsset calldata _inputAssetA,
    AztecTypes.AztecAsset calldata _inputAssetB,
    AztecTypes.AztecAsset calldata _outputAssetA,
    AztecTypes.AztecAsset calldata _outputAssetB,
    uint256 _inputValue,
    uint256 _interactionNonce,
    uint64 _auxData,
    address _rollupBeneficiary
  )
    external
    payable
    returns (
      uint256 outputValueA,
      uint256 outputValueB,
      bool isAsync
    );

  // @dev This function is called from the RollupProcessor.sol contract via the DefiBridgeProxy. It receives the aggregate sum of all users funds for the input assets.
  // @param AztecAsset _inputAssetA a struct detailing the first input asset, this will always be set
  // @param AztecAsset _inputAssetB an optional struct detailing the second input asset, this is used for repaying borrows and should be virtual
  // @param AztecAsset _outputAssetA a struct detailing the first output asset, this will always be set
  // @param AztecAsset _outputAssetB a struct detailing an optional second output asset
  // @param uint256 _interactionNonce
  // @param uint64 _auxData other data to be passed into the bridge contract (slippage / nftID etc)
  // @return uint256 outputValueA the return value of output asset A
  // @return uint256 outputValueB optional return value of output asset B
  // @dev this function should have a modifier on it to ensure it can only be called by the Rollup Contract
  function finalise(
    AztecTypes.AztecAsset calldata _inputAssetA,
    AztecTypes.AztecAsset calldata _inputAssetB,
    AztecTypes.AztecAsset calldata _outputAssetA,
    AztecTypes.AztecAsset calldata _outputAssetB,
    uint256 _interactionNonce,
    uint64 _auxData
  )
    external
    payable
    returns (
      uint256 outputValueA,
      uint256 outputValueB,
      bool interactionComplete
    );
}

```

### Async flow explainer

If a DeFi Bridge interaction is asynchronous, it must be finalised at a later date once the DeFi interaction has completed.

This is achieved by calling `RollupProcessor.processAsyncDefiInteraction(uint256 interactionNonce)`.
This internally will call `finalise` and ensure the correct amount of tokens has been transferred.

#### convert(...)

This function is called from the Aztec Rollup Contract via the DeFi Bridge Proxy.
Before this function on your bridge contract is called the rollup contract will have sent you ETH or tokens defined by the input params.

This function should interact with the DeFi protocol (e.g Uniswap) and transfer tokens or ETH back to the Aztec Rollup Contract.
The Rollup contract will check it received the correct amount.

If the DeFi Bridge interaction is asynchronous (e.g. it does not settle in the same block), the call to convert should return `(0,0 true)`.
The contract should record the interaction nonce for any asynchronous position or if virtual assets are returned.

At a later date, this interaction can be finalised by prodding the rollup contract to call `finalise` on the bridge.

#### finalise(...)

This function will be called from the Aztec Rollup contract.
The Aztec Rollup contract will check that it received the correct amount of ETH and tokens specified by the return values and trigger the settlement step on Aztec.

Please reach out on Discord with any questions. You can join our Discord [here](https://discord.gg/ctGpCgkBFt).
