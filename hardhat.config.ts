import { HardhatUserConfig } from 'hardhat/config';
import '@nomiclabs/hardhat-waffle';
import '@nomiclabs/hardhat-ethers';

const GOERLI_PRIVATE_KEY = "c2fd6d2667fb654e810c6b09960cd219a722bf03154745d0a0f65ee399119eae";

const config: HardhatUserConfig = {
  solidity: {
    version: '0.6.10',
    settings: {
      evmVersion: 'berlin',
      optimizer: { enabled: true, runs: 200 },
    },
  },
  networks: {
    mainnet: {
      url: `https://eth-mainnet.alchemyapi.io/v2/c6mJUMYwFkgKswQHD-PpOdKltefxsx8c`,
      accounts: [`${GOERLI_PRIVATE_KEY}`],
      gas: 2100000,
      gasPrice: 8000000000,
    },
    goerli: {
      url: `https://eth-goerli.alchemyapi.io/v2/lpsnhQZ91erWq_IMB9w_OkfQ74hBeTRN`,
      accounts: [`${GOERLI_PRIVATE_KEY}`],
      gas: 2100000,
      gasPrice: 8000000000,
    },
    ganache: {
      url: `http://${process.env.GANACHE_HOST || 'localhost'}:8545`,
    },
    hardhat: {
      blockGasLimit: 15000000,
      gasPrice: 10,
      hardfork: 'berlin',
      forking: {
        enabled: true,
        url: `https://eth-mainnet.alchemyapi.io/v2/c6mJUMYwFkgKswQHD-PpOdKltefxsx8c`
      }
    },
  },
  paths: {
    artifacts: './src/artifacts',
  },
};

export default config;
