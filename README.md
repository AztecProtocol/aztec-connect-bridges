# Aztec Connect Bridges

[![CircleCI](https://circleci.com/gh/AztecProtocol/aztec-connect-bridges/tree/master.svg?style=shield)](https://circleci.com/gh/AztecProtocol/aztec-connect-bridges/tree/master)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](./CODE_OF_CONDUCT.md)

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

To get started follow the steps below:

1. Fork this repository on GitHub, clone your fork and create a new branch:

   ```
   git clone https://github.com/YOUR_USERNAME/aztec-connect-bridges.git
   git checkout -b your_username/bridge-name
   ```

2. Install dependencies and build the repo:
   ```
   cd aztec-connect-bridges
   yarn setup
   ```
3. Copy and rename the following folders (e.g. rename example to uniswap):

   ```
   src/bridges/example
   src/test/example
   src/client/example
   src/specs/example
   src/deployment/example
   ```

4. Implement the bridges and tests.
   See the [example bridge](./src/bridges/example/ExampleBridge.sol), [example bridge tests](./src/test/bridges/example) and documentation of [IDefiBridge](./src/aztec/interfaces/IDefiBridge.sol) for more details.
   For a more complex example check out other bridges in this repository.

5. Debug your bridge:

   `forge test --match-contract YourBridge -vvv`

6. Write a deployment script. 
   Make a script that inherits from the `BaseDeployment.s.sol` file. The base provides helper functions for listing assets/bridges and a getter for the rollup address. Use the env variables `broadcast = false|true` and `network=mainnet|devnet|testnet` to specify how to run it, with `broadcast = true`, the `listBridge` and `listAsset` helpers will be broadcast, otherwise they are similuated as if they came from the controller. See the example scripts from other bridges, for inspiration on how to do it.

All bridges need to be submitted via PRs to this repo.
To receive a grant payment we expect the following work to be done:

1. A solidity bridge that interfaces with the protocol you are bridging to (e.g AAVE),
2. tests in Solidity that test the bridge with production values and the deployed protocol that is currently on mainnet (you should test a range of assets, edge cases and use [Forge's fuzzing abilities](https://book.getfoundry.sh/forge/fuzz-testing.html)),
3. tests cover the full contract, there are no untested functions or lines.
4. implementation of the Typescript `bridge-data.ts` class that tells a frontend developer how to use your bridge.
5. an explanation of the flows your bridge supports should be included as `spec.md`,
6. [NatSpec](https://docs.soliditylang.org/en/develop/natspec-format.html) documentation of all the functions in all the contracts which are to be deployed on mainnet.
7. A deployment script to deploy the bridge with proper configuration

Before submitting a PR for a review make sure that the following is true:

1. All the tests you wrote pass (`forge test --match-contract TestName`),
2. there are no linting errors (`yarn lint`),
3. you fetched upstream changes to your fork on GitHub and your branch has been rebased against the head of the `master` branch (**_not merged_**, if you are not sure how to rebase check out [this article](https://blog.verslu.is/git/git-rebase/)),
4. the diff contains only changes related to the PR description,
5. NatSpec documentation has already been written.
6. A spec was written
7. A deployment script was written

## SDK

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

We encourage you to first write all tests as unit tests to be able to leverage simple traces while you are debugging the bridge.
Once you make the bridge work in the unit tests environment convert the relevant tests to E2E.
Converting unit tests to E2E is straightforward because we made the `BridgeTestBase.sendDefiRollup(...)` function return the same values as `IDefiBridge.convert(...)`.

In production, the rollup contract will supply `_totalInputValue` of both input assets and use the `_interactionNonce` as a globally unique ID.
For testing, you may provide this value.

The rollup contract will send `_totalInputValue` of `_inputAssetA` and `_inputAssetB` ahead of the call to convert.
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

This is a Typescript class designed to help a developer on the frontend use your bridge.
You should implement the functions to fetch data from your bridge / L1.

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

The source of funds for any Aztec Connect transaction is an Aztec-shielded asset.
When a user interacts with an Aztec Connect Bridge contract, their identity is kept hidden, but balances sent to the bridge are public.

### Virtual Assets

Aztec uses the concept of Virtual Assets or Position tokens to represent a share of assets held by a Bridge contract.
This is far more gas efficient than minting ERC20 tokens.
These are used when the bridge holds an asset that Aztec doesn't support (e.g. Uniswap Position NFTs or other non-fungible assets).

If the output asset of any interaction is specified as "VIRTUAL", the user will receive encrypted notes on Aztec representing their share of the position, but no tokens or ETH need to be transferred.
The position tokens have an `assetId` that is the `interactionNonce` of the DeFi Bridge call.
This is globally unique.
Virtual assets can be used to construct complex flows, such as entering or exiting LP positions (e.g. one bridge contract can have multiple flows which are triggered using different input assets).

### Example flows and asset configurations

1. Swapping - 1 real input, 1 real output
2. Swapping with incentives - 1 real input, 2 real outputs (2nd output reward token)
3. Borrowing - 1 real input (collateral), 1 real output (borrowed asset, e.g. Dai), 1 virtual output (represents the position, e.g. position is a vault in MakerDao)
4. Purchasing an NFT - 1 real input, 1 virtual output (asset representing NFT)
5. Selling an NFT - 1 virtual input (asset representing NFT), 1 real output (e.g. ETH)
6. Repaying a loan - 1 real input (e.g. Dai), 1 virtual input (representing the vault/position), 1 real output (collateral, e.g. ETH)
7. Repaying a loan 2 - 1 real input (e.g. USDC), 1 virtual input (representing the position), 2 real outputs ( 1st output collateral, 2nd output reward token, e.g. AAVE)
8. Partial loan repaying - 1 real input (e.g. Dai), 1 virtual input (representing the vault/position), 1 real output (collateral, e.g. ETH), 1 virtual output (representing the vault/position)
9. Claiming fees from Uniswap position and redepositing them - 1 virtual input (represents LP position NFT), 1 virtual output (representing the modified LP position)

Please reach out on Discord with any questions. You can join our Discord [here](https://discord.gg/ctGpCgkBFt).
