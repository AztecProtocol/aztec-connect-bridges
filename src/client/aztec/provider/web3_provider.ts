import { Web3Provider } from "@ethersproject/providers";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";

export const createWeb3Provider = (ethereumProvider: EthereumProvider) => new Web3Provider(ethereumProvider);
