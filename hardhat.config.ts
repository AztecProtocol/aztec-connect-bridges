import { HardhatUserConfig } from "hardhat/config";
import "@nomiclabs/hardhat-waffle";
import "@nomiclabs/hardhat-ethers";

const getBlockNumber = () => {
  let blockNumber = 13005989;
  if (process.env.BLOCK_NUMBER) {
    blockNumber = +process.env.BLOCK_NUMBER;
  }
  return blockNumber;
};

const config: HardhatUserConfig = {
  solidity: {
    version: "0.6.10",
    settings: {
      evmVersion: "berlin",
      optimizer: { enabled: true, runs: 200 },
    },
  },
  networks: {
    ganache: {
      url: `http://${process.env.GANACHE_HOST || "localhost"}:8545`,
    },
    hardhat: {
      blockGasLimit: 15000000,
      gasPrice: 10,
      hardfork: "berlin",
      forking: {
        url:
          process.env.MAINNET_RPC_HOST ||
          "https://mainnet.infura.io/v3/9928b52099854248b3a096be07a6b23c",
        blockNumber: getBlockNumber(),
      },
    },
  },
  paths: {
    artifacts: "./src/artifacts",
  },
};

export default config;
