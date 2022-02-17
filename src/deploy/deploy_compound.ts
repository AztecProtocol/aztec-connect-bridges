import { Contract, ContractFactory, Signer } from 'ethers';
import ERC20Mintable from '../artifacts/contracts/ERC20Mintable.sol/ERC20Mintable.json';

export async function deployCompound(signer: Signer) {
  console.log('Deploying CompoundBridge...');
  const CompoundBridge = await cTokenFactory.deploy();
  console.log(`CompoundBridge address: ${CompoundBridge.address}`);
  return CompoundBridge;
}

deployCompound(owner: Signer)
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
