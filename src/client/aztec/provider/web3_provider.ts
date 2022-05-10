import { Web3Provider } from '@ethersproject/providers';
import { EthereumProvider } from './ethereum_provider';

export const createWeb3Provider = (ethereumProvider: EthereumProvider) => new Web3Provider(ethereumProvider);
