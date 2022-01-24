import { HardhatUserConfig } from 'hardhat/config';
import '@nomiclabs/hardhat-waffle';
import '@nomiclabs/hardhat-ethers';

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      { version: "0.6.6"},
      { version: "0.7.0"}
    ],
    settings: {
      evmVersion: 'berlin',
      optimizer: { enabled: true, runs: 200 },
    },
  },
  networks: {
    ganache: {
      url: `http://${process.env.GANACHE_HOST || 'localhost'}:8545`,
    },
    hardhat: {
      blockGasLimit: 15000000,
      gasPrice: 10,
      hardfork: 'berlin',
    },
  },
  paths: {
    artifacts: './src/artifacts',
  },
};

export default config;
