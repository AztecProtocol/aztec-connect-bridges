import ISwapRouter from "./artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import { addressesAreSame, Constants, approveToken, depositToWeth, approveWeth } from "./utils";

import { Contract, Signer } from "ethers";

const UNISWAP = "0xe592427a0aece92de3edee1f18e0157c05861564";

const supportedAssets = [Constants.DAI, Constants.USDC, Constants.WBTC, Constants.WETH9];

const fixEthersStackTrace = (err: Error) => {
  err.stack! += new Error().stack;
  throw err;
};

export class Uniswap {
  private contract: Contract;

  constructor(private signer: Signer) {
    this.contract = new Contract(
      UNISWAP,
      ISwapRouter.abi,
      signer
    ); 
  }

  static isSupportedAsset(assetAddress: string) {
    return supportedAssets.some(asset => addressesAreSame(assetAddress, asset));
  }

  getAddress() {
    return this.contract.address;
  }

  async swapTokens(recipient: string, outputToken: {erc20Address: string, amount: bigint, name: string}, inputToken: {erc20Address: string, amount: bigint, name: string}, fee: bigint) {
    if (!Uniswap.isSupportedAsset(outputToken.erc20Address)) {
      throw new Error('Asset not supported');
    }
    const params = {
      tokenIn: inputToken.erc20Address,
      tokenOut: outputToken.erc20Address,
      fee,
      recipient: recipient,
      deadline: `0x${BigInt(Date.now() + 36000000).toString(16)}`,
      amountOut: outputToken.amount,
      amountInMaximum: inputToken.amount,
      sqrtPriceLimitX96: 0n,
    };
    
    await approveToken(inputToken.erc20Address, this.contract.address, this.signer, inputToken.amount);

    const swapTx = await this.contract.connect(this.signer)
    .exactOutputSingle(params)
    .catch(fixEthersStackTrace);
    await swapTx.wait();
  }

  async swapFromEth(recipient: string, token: {erc20Address: string, amount: bigint, name: string}, amountInMaximum: bigint) {
    if (!Uniswap.isSupportedAsset(token.erc20Address)) {
      throw new Error('Asset not supported');
    }
    await depositToWeth(amountInMaximum, this.signer);
    if (addressesAreSame(token.erc20Address, Constants.WETH9)) {
      return;
    }
    const params = {
      tokenIn: Constants.WETH9,
      tokenOut: token.erc20Address,
      fee: 3000n,
      recipient: recipient,
      deadline: `0x${BigInt(Date.now() + 36000000).toString(16)}`,
      amountOut: token.amount,
      amountInMaximum: amountInMaximum,
      sqrtPriceLimitX96: 0n,
    };

    await approveWeth(this.contract.address, params.amountInMaximum, this.signer);

    const swapTx = await this.contract.connect(this.signer)
    .exactOutputSingle(params)
    .catch(fixEthersStackTrace);
    await swapTx.wait();
  }
}