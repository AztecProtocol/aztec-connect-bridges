# Contributing

We are looking for community members with experience writing Solidity contracts to write bridge contracts. As Aztec integrates with more Ethereum protocols, more transactions will flow through the network making it faster, cheaper and more private for everyone.

We have a grants program where you can get funding to write a custom bridge. You can find more information about the program [here](https://www.notion.so/aztecnetwork/Aztec-Grants-19896948e74b4024a458cdeddbe9574f).

In the near future, adding a custom bridge to the Aztec network will be permissionless. Currently bridges must be added to the Aztec Rollup processor contract manually by the team. This is a temporary measure as we bootstrap the network.

This repo has been built with Foundry. Given the inter-connected nature of Aztec Connect Bridges with existing mainnet protocols, we decided Foundry / forge offered the best support for testing. This repo should make debugging, mainnet-forking, impersonation and gas profiling simple. It makes sense to test Solidity contracts with Solidty not with the added complication of Ethers / Typescript.

For more information, refer to the [README](./README.md).

Please reach out on Discord with any questions. You can join our Discord [here](https://discord.gg/ctGpCgkBFt).
