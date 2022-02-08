import { HardhatUserConfig } from 'hardhat/config';
import '@typechain/hardhat';

const config: HardhatUserConfig = {
  solidity: {
    compilers: [
      {
        version: '0.8.10',
      },
    ],
    settings: {
      evmVersion: 'london',
      optimizer: { enabled: true, runs: 200 },
    },
  },
  typechain: {
    target: 'ethers-v5',
  },
  networks: {
    ganache: {
      url: `http://${process.env.GANACHE_HOST || 'localhost'}:8545`,
    },
    hardhat: {
      blockGasLimit: 15000000,
    },
  },
  paths: {
    sources: 'src/',
    artifacts: './artifacts',
  },
};

export default config;
