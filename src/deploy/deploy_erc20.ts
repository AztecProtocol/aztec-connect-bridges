import { Contract, ContractFactory, Signer } from 'ethers';
import ERC20Mintable from '../artifacts/contracts/ERC20Mintable.sol/ERC20Mintable.json';

export async function deployErc20(signer: Signer, decimals = 18) {
  console.log('Deploying ERC20...');
  const erc20Factory = new ContractFactory(ERC20Mintable.abi, ERC20Mintable.bytecode, signer);
  const erc20 = await erc20Factory.deploy();
  console.log(`ERC20 contract address: ${erc20.address}`);
  if (decimals !== 18) {
    console.log(`Changing decimals to: ${decimals}...`);
    await erc20.setDecimals(decimals);
  }
  return erc20;
}
