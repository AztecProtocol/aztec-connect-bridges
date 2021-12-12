import { Contract, ContractFactory, Signer } from 'ethers';
import ERC20Mintable from '../artifacts/contracts/ERC20Mintable.sol/ERC20Mintable.json';

export async function deployCEth(signer: Signer, decimals = 18) {
  console.log('Deploying cEth...');
  const cTokenFactory = new ContractFactory(ERC20Mintable.abi, ERC20Mintable.bytecode, signer);
  const cToken = await cTokenFactory.deploy();
  console.log(`cToken contract address: ${cToken.address}`);
  return cToken;
}

export async function deployCToken(signer: Signer, decimals = 18) {
  console.log('Deploying cToken...');
  const cTokenFactory = new ContractFactory(ERC20Mintable.abi, ERC20Mintable.bytecode, signer);
  const cToken = await cTokenFactory.deploy();
  console.log(`cToken contract address: ${cToken.address}`);
  return cToken;
}
