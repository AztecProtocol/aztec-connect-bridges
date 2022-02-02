import { Contract, Signer } from "ethers";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import WETH from "./artifacts/contracts/interfaces/IWETH.sol/WETH.json";

export const addressesAreSame = (a: string, b: string) =>
  a.toLowerCase() === b.toLowerCase();

export const fixEthersStackTrace = (err: Error) => {
  err.stack! += new Error().stack;
  throw err;
};

export class Constants {
  static readonly WETH9 = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";
  static readonly DAI = "0x6b175474e89094c44da98b954eedeac495271d0f";
  static readonly USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
  static readonly WBTC = "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599";
  static readonly EUR = "0xdB25f211AB05b1c97D595516F45794528a807ad8";
  static readonly ETH = "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE";
}

export interface SendTxOptions {
  gasPrice?: bigint;
  gasLimit?: number;
}

export const assetToArray = (asset: AztecAsset) => [
  asset.id || 0,
  asset.erc20Address || "0x0000000000000000000000000000000000000000",
  asset.assetType || 0,
];

export enum AztecAssetType {
  NOT_USED,
  ETH,
  ERC20,
  VIRTUAL,
}

export interface AztecAsset {
  id?: number;
  assetType?: AztecAssetType;
  erc20Address?: string;
}

export async function getTokenBalance(
  tokenAddress: string,
  address: string,
  signer: Signer
) {
  const tokenContract = new Contract(tokenAddress, ERC20.abi, signer);
  const currentBalance = await tokenContract.balanceOf(address);
  return currentBalance.toBigInt();
}

export async function approveToken(
  tokenAddress: string,
  spender: string,
  signer: Signer,
  amount: bigint
) {
  const tokenContract = new Contract(tokenAddress, ERC20.abi, signer);
  const approved = await tokenContract.approve(spender, amount);
  await approved.wait();
}

export async function transferToken(
  tokenAddress: string,
  recipient: string,
  signer: Signer,
  amount: bigint
) {
  const tokenContract = new Contract(tokenAddress, ERC20.abi, signer);
  const approved = await tokenContract.transfer(recipient, amount);
  await approved.wait();
}

export function createWethContract(signer: Signer) {
  return new Contract(Constants.WETH9, WETH.abi, signer).connect(signer);
}

export async function approveWeth(spender: string, amount: bigint, signer: Signer) {
  const wethContract = createWethContract(signer);
  const approveTx = await wethContract.approve(spender, amount);
  await approveTx.wait();
}

export async function getWethBalance(address: string, signer: Signer) {
  const wethContract = createWethContract(signer);
  const currentBalance = await wethContract.balanceOf(address);
  return currentBalance.toBigInt();
}

export async function depositToWeth(amount: bigint, signer: Signer) {
  const wethContract = createWethContract(signer);
  const address = await signer.getAddress();
  const balance = (await wethContract.balanceOf(address)).toBigInt();
  if (balance < amount) {
    const amountToAdd = amount - balance;
    const depositTx = await wethContract.deposit({ value: amountToAdd });
    await depositTx.wait();
  }
}
