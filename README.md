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
3. Create the following folders for your bridge (e.g. replace example with uniswap):

   ```
   specs/bridges/example
   src/bridges/example
   src/test/bridges/example
   src/deployment/example
   ```

4. Implement the bridges and tests.
   See the [example bridge](./src/bridges/example/ExampleBridge.sol), [example bridge tests](./src/test/bridges/example) and documentation of [IDefiBridge](./src/aztec/interfaces/IDefiBridge.sol) for more details.
   For a more complex example check out other bridges in this repository.
5. Debug your bridge:

   `forge test --match-contract YourBridge -vvv`

6. Write a deployment script.
   Make a script that inherits from the `BaseDeployment.s.sol` file. The base provides helper functions for listing assets/bridges and a getter for the rollup address.  
   Use the env variables `SIMULATE_ADMIN=false|true` and `NETWORK=mainnet|devnet|testnet|DONT_CARE` to specify how to run it. (Note: DONT_CARE is relevant when deploying to the local devnet, more information on this is outlined below)  
   With `SIMULATE_ADMIN=true`, the `listBridge` and `listAsset` helpers will be impersonating an account with access to list, otherwise they are broadcasted. See the example scripts from other bridges for inspiration on how to write the scripts.

7. Using the local devnet is the default integration testing environment, it can take a bit of effort to set up but this section will guide you through it! If you are a grantee and have received access to the partner testnet you can find details of that in section 8.

   ### Getting the local devnet up and running

   In the majority of cases you will want to run the local devnet as a mainnet fork, to allow you to test against mainnet protocols.

   Inside this repo there is a `/local_devnet` folder that contains the required resources. The `docker-compose.fork.yml` contains a compose configuration that will launch:

   1. A local node (anvil).
   2. Deploy our contracts.
   3. Run a local sequencer.

   If you do not have docker installed please follow the instructions [here](https://docs.docker.com/compose/).

   To run the devnet please execute the following commands.

   > Note: A more in-depth overview of the local devnet can be found over at our [documentation](https://docs.aztec.network/developers/local-devnet).

   ```bash
   # Setup env
   export FORK_URL={A mainnet RPC url} # Get one of these from infura / alchemy
   export CHAIN_ID=3567
   export NETWORK=DONT_CARE # DONT_CARE means you are not targeting existing deployments (devnet, testnet etc.)

   # Run devnet
   docker-compose -f local_devnet/docker-compose.fork.yml up
   ```

   Once your sequencer is up and running it will output `falafel-1 | [Timestamp] Server: Ready to receive txs.` to the logs.

   ### Deploying a bridge

   Open up another terminal and enter:

   ```bash
   # Setup env
   # ---------
   # For the below script you will need to have both `curl` and `jq` installed.
   # It loads required ENV_VARS (the ROLLUP_PROCESSOR_ADDRESS) into your ENV. An explainer for this script can be found
   # in the collapsed section below
   source ./local_devnet/export_addresses.sh
   # Deploy to our local fork
   export RPC=http://localhost:8545
   # Deploy using the default anvil key as anvil is our current local node
   export PRIV_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
   # DONT_CARE means we are not targeting any development environments
   export NETWORK=DONT_CARE
   # Do not run the deploy scripts in simulation mode
   export SIMULATE_ADMIN=false

   # Example deployment script
   forge script --fork-url $RPC --private-key $PRIV_KEY <NAME_OF_DEPLOYMENT_SCRIPT> --sig "<FUNCTION_SIF>" --broadcast

   # Example script reading the current assets and bridges
   forge script --fork-url $RPC AggregateDeployment --sig "readStats()"
   ```

   Note any deployments will need to be made from the default anvil deployer key. For simplicity the fork uses anvil's default address has all admin roles on the deployed rollup.

   If you need to view the contract addresses of the core rollup contracts in your local devnet you can run the `./local_devnet/export_addresses.sh` script and it will print them.

   <details>
   <summary> Click here to read about how export_addresses.sh works under the hood </summary>
   In your deployment scripts you will want to know the address that the rollup processor has been deployed to on your fork. You can easily get this information by querying the contracts container. After a successful deployment, it will serve the deployed contract addresses on port `8547`. Curling this endpoint will yield the following json with all of the deployment addresses.

   ```bash
   curl http://localhost:8547
   {
     "PROXY_ADMIN_ADDRESS": "0x3E661784267F128e5f706De17Fac1Fc1c9d56f30",
     "DAI_CONTRACT_ADDRESS": "0x6B175474E89094C44Da98b954EedeAC495271d0F",
     "PERMIT_HELPER_CONTRACT_ADDRESS": "0xAe9Ed85dE2670e3112590a2BB17b7283ddF44d9c",
     "DEPLOYER_ADDRESS": "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266",
     "BTC_CONTRACT_ADDRESS": "0x0000000000000000000000000000000000000000",
     "GAS_PRICE_FEED_CONTRACT_ADDRESS": "0x169E633A2D1E6c10dD91238Ba11c4A708dfEF37C",
     "DEFI_PROXY_CONTRACT_ADDRESS": "0xF6a8aD553b265405526030c2102fda2bDcdDC177",
     "VERIFIER_CONTRACT_ADDRESS": "0xeC1BB74f5799811c0c1Bff94Ef76Fb40abccbE4a",
     "PROXY_DEPLOYER_CONTRACT_ADDRESS": "0x6732128F9cc0c4344b2d4DC6285BCd516b7E59E6",
     "VERSION": 2,
     "FAUCET_CONTRACT_ADDRESS": "0xc0c5618f0F3Fa66b496F2940f373DC366d765BAe",
     "BRIDGE_DATA_PROVIDER_CONTRACT_ADDRESS": "0xe14058B1c3def306e2cb37535647A04De03Db092",
     "DAI_PRICE_FEED_CONTRACT_ADDRESS": "0x773616E4d11A78F511299002da57A0a94577F1f4",
     "SAFE_ADDRESS": "0x7095057A08879e09DC1c0a85520e3160A0F67C96",
     "ROLLUP_CONTRACT_ADDRESS": "0x7F2498c7073D143094cA6Ea5ABe58DaA56DBfF2E",
     "FEE_DISTRIBUTOR_ADDRESS": "0x8f119cd256a0FfFeed643E830ADCD9767a1d517F"
   }%
   ```

   The export_addresses.sh script will poll each of the addresses with `jq` and add them to your path.
   The step is required when performing subsequent bridge deployments to your fork, as the base deployment script will look for the `ROLLUP_PROCESSOR_ADDRESS` inside your environment variables.

   </details>

   For more information about how to configure the sequencer to run your bridge, please visit our [documentation](https://docs.aztec.network/developers/local-devnet).

8) Testing/using your deployment script against testnet

   > **Info**
   > Due to extreme load our testnet environment have become reserved for partners. Please reach out to `devrel@aztecprotocol.com` if you wish to receive access. Thank you for understanding!
   >
   > To get the local devnet up and running please consult our [documentation](https://docs.aztec.network/developers/local-devnet). Note that if you are building against an existing protocol (e.g. aave, compound, uniswap) you will want to run the [fork](https://docs.aztec.network/developers/local-devnet#mainnet-fork-with-bridge-contracts) version of the local devnet (details can be found in the section above).

   To run your deployment script, you need to set the environment up first, this include specifying the RPC you will be sending the transactions to and the environment variables from above. You can do it using a private key, or even with a Ledger or Trezor, see the foundry book for more info on using hardware wallets.

   ```bash
   # Use --broadcast when you intend to broadcast the tx's, otherwise it will just simulate
   # --ffi is used to allow outside calls, which is used to fetch the latest Rollup address
   # on testnet this will fetch from the Aztec endpoints, on mainnet, this will lookup the `rollup.aztec.eth` ens
   export RPC=https://aztec-connect-testnet-eth-host.aztec.network:8545/{TESTNET_API_KEY}
   export PRIV_KEY=<DEV_KEY> # If using a private-key directly
   export NETWORK=testnet # When using the testnet
   export SIMULATE_ADMIN=false # When you want to broadcast, use `true` if simulating admin
   forge script --fork-url $RPC --ffi --private-key $PRIV_KEY <NAME_OF_DEPLOYMENT_SCRIPT> --sig "<FUNCTION_SIG>" --broadcast

   # Example script reading the current assets and bridges:
   forge script --fork-url $RPC --ffi AggregateDeployment --sig "readStats()"
   ```

All bridges need to be submitted via PRs to this repo.
To receive a grant payment we expect the following work to be done:

1. A solidity bridge that interfaces with the protocol you are bridging to (e.g AAVE),
2. tests in Solidity that test the bridge with production values and the deployed protocol that is currently on mainnet (you should test a range of assets, edge cases and use [Forge's fuzzing abilities](https://book.getfoundry.sh/forge/fuzz-testing.html)),
3. tests cover the full contract, there are no untested functions or lines.
4. an explanation of the flows your bridge supports should be included as `spec.md`,
5. [NatSpec](https://docs.soliditylang.org/en/develop/natspec-format.html) documentation of all the functions in all the contracts which are to be deployed on mainnet,
6. a deployment script to deploy the bridge with proper configuration,
7. Subsidy contract has been integrated (see the [Subsidy integration section](#subsidy-integration) for details).

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

You can find more information about setting up connections to bridge contracts with the SDK on the [Ethereum Interactions](https://docs.aztec.network/sdk/usage/ethereum-interaction) page of the docs.

## Testing methodology

This repo includes an Infura key that allows forking from mainnet.
We have included helpers to make testing easier (see [example bridge tests](./src/test/bridges/example)).

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
   Disadvantage of this approach is that you have to take care of transferring tokens to and from the bridge (this is handled by the DefiBridgeProxy contract in the production environment).
   This type of test can be considered to be a unit test and an example of such a test is [here](./src/test/bridges/example/ExampleUnit.t.sol).

2. In the second approach we construct a `bridgeCallData`, we mock proof data and verifier's response, and we pass this data directly to the RollupProcessor's `processRollup(...)` function.
   The purpose of this test is to test the bridge in an environment that is as close to the final deployment as possible without spinning up all the rollup infrastructure (sequencer, proof generator etc.).
   This test can be considered an end-to-end test of the bridge and an example of such a test is [here](./src/test/bridges/example/ExampleE2E.t.sol).

We encourage you to first write all tests as unit tests to be able to leverage simple traces while you are debugging the bridge.
Once you make the bridge work in the unit tests environment convert the relevant tests to E2E.
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

The rollup contract expects a bridge to have approved for transfer by the `rollupAddress` the ERC20 tokens that are returned via `outputValueA` or `outputValueB` for a given asset.
The `DeFiBridgeProxy` will attempt to recover the tokens by calling `transferFrom(bridgeAddress, rollupAddress, amount)` for these values once `bridge.convert()` or `bridge.finalise()` have executed (in production and in end-to-end tests).
In unit tests it is expected that you transfer these tokens on your own.

ETH is returned to the rollup from a bridge by calling the payable function with a `msg.value` `rollupContract.receiveETH(uint256 interactionNonce)`.
You must also set the `outputValue` of the corresponding `outputAsset` (A or B) to be the amount of ETH sent.

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

### Asset Types

There are 3 types of assets:

1. `ETH`,
2. `ERC20`,
3. `VIRTUAL`.

We call **ETH** and **ERC20** real assets.

Virtual assets behave similarly to the real ones but the difference is that they don't have any token representation on L1 and exist solely within the Aztec network as a cryptographic value note.

To be more explicit, this is what happens when users initiate a bridge call with **ERC20** tokens on input and output:

1. Users' cryptographic value notes on L2 are destroyed, and they receive cryptographic claim notes which make them eligible for the results of the interaction (output tokens),
2. `rollup provider` creates a rollup block and sends it to the `RollupProcessor` contract (the rollup block contains the corresponding bridge call),
3. `RollupProcessor` calls `DefiBridgeProxy`'s `convert(...)` function via delegate call (input and output assets are of `ERC20` type),
4. `DefiBridgeProxy` contract transfers `totalInputValue` of input tokens to the `bridge`,
5. `DefiBridgeProxy` calls the `bridge`'s convert function,
6. in the convert function `bridge` approves `RollupProcessor` to spend `outputValue[A,B]` of output tokens,
7. `DefiBridgeProxy` pulls the `outputValue[A,B]` of output tokens to `RollupProcessor`,
8. once the interaction is finished `rollup provider` submits a claim on behalf of each user who partook in the interaction (claim note is destroyed and new value note is created).

The flow when dealing with **ETH** on input and output is very similar to the **ERC20** one.
The difference is that **ETH** gets passed to the bridge directly as a `msg.value` of the `convert(...)` function call.
When returning it, the bridge calls `RollupProcessor.receiveEthFromBridge{value: outputValue}(uint256 _interactionNonce)`.

The flow with **VIRTUAL** asset on the input and output is quite different from the real ones:

1. Users' cryptographic value notes on L2 are destroyed, and they receive cryptographic claim notes which make them eligible for the results of the interaction (output tokens),
2. `rollup provider` creates a rollup block and sends it to the `RollupProcessor` contract (the rollup block contains the corresponding bridge call),
3. `RollupProcessor` calls `DefiBridgeProxy`'s `convert(...)` function via delegate call (input and output assets are of `ERC20` type),
4. `DefiBridgeProxy` calls the `bridge`'s convert function,
5. `DefiBridgeProxy` transfers the `outputValue[A,B]` of output tokens to `RollupProcessor`,
6. once the interaction is finished `rollup provider` submits a claim on behalf of each user who partook in the interaction (claim note is destroyed and new value note is created)

We can notice that with virtual assets there are no actual transfers on L1.
Virtual assets are used simply as a packet of information which can be used by the bridge to represent some form of ownership.
This is far more gas efficient than minting and transferring ERC20 tokens, and generally they are recommended to be used when the bridge holds an asset which is not natively supported by `RollupProcessor` contract (e.g. NFTs).

When virtual assets are returned from a `convert(...)` function their `assetId` is set to the `interactionNonce` of the bridge call.
An `interactionNonce` is globally unique.
Virtual assets can be used to construct complex flows, such as entering or exiting LP positions.

> Note 1: Value notes represent ownership of assets on L2.

> Note 2: We don't call `bridge`'s `convert(...)` method directly from the `RollupProcessor` in order to separate the asset transfer functionality from the main contract.

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

1. `_criteria` is a value defining a specific bridge call.
   This value is expected to be computed differently in different bridges and should identify a specific bridge flow (e.g. it can be a hash of the input and output token addresses or just the `_auxData` or whatever makes sense).
2. `_gasUsage` is an estimated gas consumption of the bridge call for a given `_criteria`.
   This is used as an upper limit for subsidy.
   If this is set correctly, at maximum less than 100% of the call should be covered since the subsidy computation is only based on base fee and is not taking tips into consideration.
3. `_minGasPerMinute` is the minimum amount of gas per minute that subsidizer has to subsidize.
   In general, we recommend this value to be computed in such a way that the subsidy funder has to fund at least 1 call a day (in such a case compute the value as `_gasUsage / (24 * 60)`).
   This value is set from the bridge in order to avoid a griefing attack (malicious subsidy funder setting a subsidy with very low `minGasPerMinute` value and effectively blocking everyone else from subsidizing the given bridge and criteria).

There are 2 versions of this method.
In the first one the parameters are single values.
In the second one the parameters are arrays of values.

The second required call is calling the `claimSubsidy(...)` function from within the `convert(...)` method.
This method has 2 parameters:

1. `_criteria` same as above,
2. `_rollupBeneficiary` is the address of the beneficiary.
   This value is passed to the `convert(...)` function.

For more info on how the Subsidy works see the documentation in the [Subsidy.sol](./src/aztec/Subsidy.sol) file.

See the [example bridge](./src/bridges/example/ExampleBridge.sol) for an example subsidy integration.

## Contact

Please reach out on Discord with any questions. You can join our Discord [here](https://discord.gg/ctGpCgkBFt).
