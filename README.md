# Aztec Connectors

[![CircleCI](https://circleci.com/gh/AztecProtocol/aztec-connect-bridges/tree/master.svg?style=shield)](https://circleci.com/gh/AztecProtocol/aztec-connect-bridges/tree/master)
[![Contributor Covenant](https://img.shields.io/badge/Contributor%20Covenant-2.1-4baaaa.svg)](./CODE_OF_CONDUCT.md)

This repo has been built with Foundry.
Given the interconnected nature of Aztec Connector contracts with existing mainnet protocols, we decided Foundry / Forge offered the best support for testing.
This repo should make debugging, mainnet-forking, impersonation and gas profiling simple.
It makes sense to test Solidity contracts with Solidity, not with the added complication of Ethers / Typescript.

**Connector contracts** and **Bridge contracts** are the same thing and the terms are used interchangeably.

> Aztec Connector contracts used to be called Bridge contracts. The name has been updated to reduce confusion around the contract behavior. Connector contracts are not bridging between separate blockchains as is often the case when referring to a bridge.References to bridges have been updated in the documentation and relevant READMEs, but not in the source code, so you will continue to see references to bridges.

## Writing a Connector Contract

Developing a connector is simple.
It is done entirely in Solidity and no knowledge of cryptography underpinning Aztec Connect is required.
Users of your connector contract will get the full benefits of ironclad privacy and 10-30x gas savings.

> Note: Currently adding a new connector or asset to Aztec Connect is permissioned and requires our approval.
> Once Aztec Connect leaves beta this won't be the case anymore and developing a connector will become completely permissionless.

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

4. Implement the connectors and tests.
   See the [example connector](./src/bridges/example/ExampleBridge.sol), [example connector tests](./src/test/bridges/example) and documentation of [IDefiBridge](./src/aztec/interfaces/IDefiBridge.sol) for more details.
   For a more complex example check out other connectors in this repository.
5. Debug your connector:

   `forge test --match-contract YourConnector -vvv`

6. Write a deployment script.
   Make a script that inherits from the `BaseDeployment.s.sol` file. The base provides helper functions for listing assets/connectors and a getter for the rollup address.  
   Use the env variables `simulateAdmin=false|true` and `network=mainnet|devnet|testnet` to specify how to run it.  
   With `simulateAdmin=true`, the `listBridge` and `listAsset` helpers will be impersonating an account with access to list, otherwise they are broadcasted. See the example scripts from other connectors for inspiration on how to write the scripts.

7. Testing/using your deployment script
   To run your deployment script, you need to set the environment up first, this include specifying the RPC you will be sending the transactions to and the environment variables from above. You can do it using a private key, or even with a Ledger or Trezor, see the foundry book for more info on using hardware wallets.

   ```bash
   # Use --broadcast when you intend to broadcast the tx's, otherwise it will just simulate
   # When using the testnet, add --legacy, Ganache and EIP-1559 is not the best friends
   # --ffi is used to allow outside calls, which is used to fetch the latest Rollup address
   # on testnet this will fetch from the Aztec endpoints, on mainnet, this will lookup the `rollup.aztec.eth` ens
   export RPC=https://aztec-connect-testnet-eth-host.aztec.network:8545
   export PRIV_KEY=<DEV_KEY> # If using a private-key directly
   export network=testnet # When using the testnet
   export simulateAdmin=false # When you want to broadcast, use `true` if simulating admin
   forge script --fork-url $RPC --ffi --legacy --private-key $PRIV <NAME_OF_DEPLOYMENT_SCRIPT> --sig "<FUNCTION_SIG>" --broadcast

   # Example script reading the current assets and connectors:
   forge script --fork-url $RPC --ffi AggregateDeployment --sig "readStats()"
   ```

All connectors need to be submitted via PRs to this repo.
To receive a grant payment we expect the following work to be done:

1. A solidity connector that interfaces with the protocol you are bridging to (e.g AAVE),
2. tests in Solidity that test the connector with production values and the deployed protocol that is currently on mainnet (you should test a range of assets, edge cases and use [Forge's fuzzing abilities](https://book.getfoundry.sh/forge/fuzz-testing.html)),
3. tests cover the full contract, there are no untested functions or lines.
4. implementation of the Typescript `bridge-data.ts` class that tells a frontend developer how to use your connector.
5. an explanation of the flows your connector supports should be included as `spec.md`,
6. [NatSpec](https://docs.soliditylang.org/en/develop/natspec-format.html) documentation of all the functions in all the contracts which are to be deployed on mainnet,
7. a deployment script to deploy the connector with proper configuration,
8. Subsidy contract has been integrated (see the [Subsidy integration section](#subsidy-integration) for details).

Before submitting a PR for a review make sure that the following is true:

1. All the tests you wrote pass (`forge test --match-contract TestName`),
2. there are no linting errors (`yarn lint`),
3. you fetched upstream changes to your fork on GitHub and your branch has been rebased against the head of the `master` branch (**_not merged_**, if you are not sure how to rebase check out [this article](https://blog.verslu.is/git/git-rebase/)),
4. the diff contains only changes related to the PR description,
5. NatSpec documentation has already been written,
6. a spec was written,
7. a deployment script was written,
8. Subsidy has been integrated.

## SDK

You can find more information about setting up connections to connector contracts with the SDK on the [Ethereum Interactions](https://docs.aztec.network/sdk/usage/ethereum-interaction) page of the docs.

## Testing methodology

This repo includes an Infura key that allows forking from mainnet.
We have included helpers to make testing easier (see [example connector tests](./src/test/bridges/example)).

In production a connector is called by a user creating a client side proof via the Aztec SDK.
These transaction proofs are sent to a rollup provider for aggregation.
The rollup provider then sends the aggregate rollup proof with the sum of all users' proofs for a given `bridgeCallData` to your connector contract.

A `bridgeCallData` uniquely defines the expected inputs/outputs of a DeFi interaction.
It is a `uint256` that represents a bit-string containing multiple fields.
When unpacked its data is used to create a BridgeData struct in the rollup processor contract.

Structure of the bit-string is as follows (starting at the least significant bit):

| bit position | bit length | definition        | description                                        |
| ------------ | ---------- | ----------------- | -------------------------------------------------- |
| 0            | 32         | `bridgeAddressId` | id of bridge/connector smart contract address      |
| 32           | 30         | `inputAssetA`     | asset id of 1st input asset                        |
| 62           | 30         | `inputAssetB`     | asset id of 1st input asset                        |
| 92           | 30         | `outputAssetA`    | asset id of 1st output asset                       |
| 122          | 30         | `outputAssetB`    | asset id of 2nd output asset                       |
| 152          | 32         | `bitConfig`       | flags that describe asset types                    |
| 184          | 64         | `auxData`         | custom auxiliary data for connector-specific logic |

Bit Config Definition:

| bit | meaning           |
| --- | ----------------- |
| 0   | secondInputInUse  |
| 1   | secondOutputInUse |

> Note 1: Last 8 bits of `bridgeCallData` bit-string are wasted because the circuits don't support values of full 256 bits (248 is the largest multiple of 8 that we can use).

> Note 2: `bitConfig` is 32 bits large even though we only use 2 bits because we need it to be future proofed (e.g. we might add NFT support, and we would need new bit flag for that).

The rollup contract uses this to construct the function parameters to pass into your connector contract (via `convert(...)` function).
It calls your connector with a fixed amount of gas via a `delegateCall` via the `DefiBridgeProxy.sol` contract.

We decided to have 2 separate approaches of connector testing:

1. In the first one it is expected that you call convert function directly on the connector contract.
   This allows for simple debugging because execution traces are simple.
   Disadvantage of this approach is that you have to take care of transferring tokens to and from the connector (this is handled by the DefiBridgeProxy contract in the production environment).
   This type of test can be considered to be a unit test and an example of such a test is [here](./src/test/bridges/example/ExampleUnit.t.sol).

2. In the second approach we construct a `bridgeCallData`, we mock proof data and verifier's response, and we pass this data directly to the RollupProcessor's `processRollup(...)` function.
   The purpose of this test is to test the connector in an environment that is as close to the final deployment as possible without spinning up all the rollup infrastructure (sequencer, proof generator etc.).
   This test can be considered an end-to-end test of the connector and an example of such a test is [here](./src/test/bridges/example/ExampleE2E.t.sol).

We encourage you to first write all tests as unit tests to be able to leverage simple traces while you are debugging the connector.
Once you make the connector work in the unit tests environment convert the relevant tests to E2E.
Converting unit tests to E2E is straightforward because we made the `ROLLUP_ENCODER.processRollupAndGetBridgeResult()` function return the same values as `IDefiBridge.convert(...)`.

In production, the rollup contract will supply `_totalInputValue` of both input assets and use the `_interactionNonce` as a globally unique ID.
For testing, you may provide this value.

The rollup contract will send `_totalInputValue` of `_inputAssetA` and `_inputAssetB` ahead of the call to convert.
In production, the rollup contract already has these tokens as they are the users' funds.
For testing use the `deal` method from the [forge-std](https://github.com/foundry-rs/forge-std)'s `Test` class (see [ExampleUnit.t.sol](./src/test/bridges/example/ExampleUnit.t.sol) for details).
This method prefunds the rollup with sufficient tokens to enable the transfer.

After extending the `BridgeTestBase` or `Test` class simply call:

```solidity
  deal(address(dai), address(rollupProcessor), amount);
```

This will set the balance of the rollup to the amount required.

## Sending Tokens Back to the Rollup

The rollup contract expects a connector to have approved for transfer by the `rollupAddress` the ERC20 tokens that are returned via `outputValueA` or `outputValueB` for a given asset.
The `DeFiBridgeProxy` will attempt to recover the tokens by calling `transferFrom(connectorAddress, rollupAddress, amount)` for these values once `connector.convert()` or `connector.finalise()` have executed (in production and in end-to-end tests).
In unit tests it is expected that you transfer these tokens on your own.

ETH is returned to the rollup from a connector by calling the payable function with a `msg.value` `rollupContract.receiveETH(uint256 interactionNonce)`.
You must also set the `outputValue` of the corresponding `outputAsset` (A or B) to be the amount of ETH sent.

This repo supports TypeChain so all Typescript bindings will be auto generated and added to the `typechain-types` folder.

### bridge-data.ts

This is a Typescript class designed to help a developer on the frontend use your connector.
You should implement the functions to fetch data from your connector / L1.

## Aztec Connect Background

You can also find more information on the [Aztec docs site](https://docs.aztec.network).

### What is Aztec?

Aztec is a privacy focussed L2, that enables cheap private interactions with Layer 1 smart contracts and liquidity, via a process called DeFi Aggregation.
We use advanced zero-knowledge technology "zk-zk rollups" to add privacy and significant gas savings any Layer 1 protocol via Aztec Connect connectors.

#### What is a Connector?

A connector is a Layer 1 Solidity contract deployed on mainnet that conforms a DeFi protocol to the interface the Aztec rollup expects.
This allows the Aztec rollup contract to interact with the DeFi protocol via the connector.

A connector contract models any Layer 1 DeFi protocol as an asynchronous asset swap. You can specify up to two input assets and two output assets per connector.

#### How does this work?

Users who have shielded assets on Aztec can construct a zero-knowledge proof instructing the Aztec rollup contract to make an external L1 contract call.

Rollup providers batch multiple L2 transaction intents on the Aztec Network together in a rollup.
The rollup contract then makes aggregate transaction against L1 DeFi contracts and returns the funds pro-rata to the users on L2.

#### How much does this cost?

Aztec connect transactions can be batched together into one rollup.
Each user in the batch pays a base fee to cover the verification of the rollup proof and their share of the L1 DeFi transaction gas cost.
A single Aztec Connect transaction requires 3 base fees or approximately ~8000 gas.

The user then pays their share of the L1 DeFi transaction.
The rollup will call a connector contract with a fixed deterministic amount of gas so the total fee is simple ~8000 gas + BRIDGE_GAS / BATCH_SIZE.

#### What is private?

The source of funds for any Aztec Connect transaction is an Aztec-shielded asset.
When a user interacts with an Aztec Connector contract, their identity is kept hidden, but balances sent to the connector are public.

### Asset Types

There are 3 types of assets:

1. `ETH`,
2. `ERC20`,
3. `VIRTUAL`.

We call **ETH** and **ERC20** real assets.

Virtual assets behave similarly to the real ones but the difference is that they don't have any token representation on L1 and exist solely within the Aztec network as a cryptographic value note.

To be more explicit, this is what happens when users initiate a connector call with **ERC20** tokens on input and output:

1. Users' cryptographic value notes on L2 are destroyed, and they receive cryptographic claim notes which make them eligible for the results of the interaction (output tokens),
2. `rollup provider` creates a rollup block and sends it to the `RollupProcessor` contract (the rollup block contains the corresponding connector call),
3. `RollupProcessor` calls `DefiBridgeProxy`'s `convert(...)` function via delegate call (input and output assets are of `ERC20` type),
4. `DefiBridgeProxy` contract transfers `totalInputValue` of input tokens to the `connector`,
5. `DefiBridgeProxy` calls the `connector`'s convert function,
6. in the convert function `connector` approves `RollupProcessor` to spend `outputValue[A,B]` of output tokens,
7. `DefiBridgeProxy` pulls the `outputValue[A,B]` of output tokens to `RollupProcessor`,
8. once the interaction is finished `rollup provider` submits a claim on behalf of each user who partook in the interaction (claim note is destroyed and new value note is created).

The flow when dealing with **ETH** on input and output is very similar to the **ERC20** one.
The difference is that **ETH** gets passed to the connector directly as a `msg.value` of the `convert(...)` function call.
When returning it, the connector calls `RollupProcessor.receiveEthFromBridge{value: outputValue}(uint256 _interactionNonce)`.

The flow with **VIRTUAL** asset on the input and output is quite different from the real ones:

1. Users' cryptographic value notes on L2 are destroyed, and they receive cryptographic claim notes which make them eligible for the results of the interaction (output tokens),
2. `rollup provider` creates a rollup block and sends it to the `RollupProcessor` contract (the rollup block contains the corresponding bridge call),
3. `RollupProcessor` calls `DefiBridgeProxy`'s `convert(...)` function via delegate call (input and output assets are of `ERC20` type),
4. `DefiBridgeProxy` calls the `connector`'s convert function,
5. `DefiBridgeProxy` transfers the `outputValue[A,B]` of output tokens to `RollupProcessor`,
6. once the interaction is finished `rollup provider` submits a claim on behalf of each user who partook in the interaction (claim note is destroyed and new value note is created)

We can notice that with virtual assets there are no actual transfers on L1.
Virtual assets are used simply as a packet of information which can be used by the connector to represent some form of ownership.
This is far more gas efficient than minting and transferring ERC20 tokens, and generally they are recommended to be used when the connector holds an asset which is not natively supported by `RollupProcessor` contract (e.g. NFTs).

When virtual assets are returned from a `convert(...)` function their `assetId` is set to the `interactionNonce` of the connector call.
An `interactionNonce` is globally unique.
Virtual assets can be used to construct complex flows, such as entering or exiting LP positions.

> Note 1: Value notes represent ownership of assets on L2.

> Note 2: We don't call `connector`'s `convert(...)` method directly from the `RollupProcessor` in order to separate the asset transfer functionality from the main contract.

> Note 3: The fact that it's currently impossible to return a virtual assets with the same `assetId` from multiple `convert(...)` function calls is a bit limiting and we might change it in the future.

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

## Subsidy integration

There are 2 calls the bridge has to do for the subsidy to work.
The first one is calling `setGasUsageAndMinGasPerMinute(...)` from constructor or any other function which is called before `convert(...)` method.
This method has 3 parameters:

1. `_criteria` is a value defining a specific connector call.
   This value is expected to be computed differently in different connectors and should identify a specific connector flow (e.g. it can be a hash of the input and output token addresses or just the `_auxData` or whatever makes sense).
2. `_gasUsage` is an estimated gas consumption of the connector call for a given `_criteria`.
   This is used as an upper limit for subsidy.
   If this is set correctly, at maximum less than 100% of the call should be covered since the subsidy computation is only based on base fee and is not taking tips into consideration.
3. `_minGasPerMinute` is the minimum amount of gas per minute that subsidizer has to subsidize.
   In general, we recommend this value to be computed in such a way that the subsidy funder has to fund at least 1 call a day (in such a case compute the value as `_gasUsage / (24 * 60)`).
   This value is set from the connector in order to avoid a griefing attack (malicious subsidy funder setting a subsidy with very low `minGasPerMinute` value and effectively blocking everyone else from subsidizing the given connector and criteria).

There are 2 versions of this method.
In the first one the parameters are single values.
In the second one the parameters are arrays of values.

The second required call is calling the `claimSubsidy(...)` function from within the `convert(...)` method.
This method has 2 parameters:

1. `_criteria` same as above,
2. `_rollupBeneficiary` is the address of the beneficiary.
   This value is passed to the `convert(...)` function.

For more info on how the Subsidy works see the documentation in the [Subsidy.sol](./src/aztec/Subsidy.sol) file.

See the [example connector](./src/bridges/example/ExampleBridge.sol) for an example subsidy integration.

## Contact

Please reach out on Discord with any questions. You can join our Discord [here](https://discord.gg/ctGpCgkBFt).
