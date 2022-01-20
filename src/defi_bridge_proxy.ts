import { Provider, Web3Provider } from "@ethersproject/providers";
import { Contract, ContractFactory, ethers, Signer } from "ethers";

import abi from "./artifacts/contracts/DefiBridgeProxy.sol/DefiBridgeProxy.json";

import ISwapRouter from "./artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import WETH from "./artifacts/contracts/interfaces/IWETH.sol/WETH.json";

const fixEthersStackTrace = (err: Error) => {
  err.stack! += new Error().stack;
  throw err;
};

export interface SendTxOptions {
  gasPrice?: bigint;
  gasLimit?: number;
}

const assetToArray = (asset: AztecAsset) => [
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

export interface MyToken {
  amount: bigint;
  erc20Address: string;
}

export class DefiBridgeProxy {
  private contract: Contract;
  private uniswapContract: Contract;
  private WETH9: string;

  constructor(public address: string, signer: Signer) {
    this.contract = new Contract(this.address, abi.abi, signer);
    this.WETH9 = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";

    this.uniswapContract = new Contract(
      "0xe592427a0aece92de3edee1f18e0157c05861564",
      ISwapRouter.abi,
      signer
    );
  }

  static async deploy(signer: Signer) {
    const factory = new ContractFactory(abi.abi, abi.bytecode, signer);
    const contract = await factory.deploy();
    return new DefiBridgeProxy(contract.address, signer);
  }

  async deployBridge(signer: Signer, bridgeAbi: any, args: any[]) {
    const factory = new ContractFactory(bridgeAbi.abi, bridgeAbi.bytecode, signer);
    const contract = await factory.deploy(...args);
    return contract.address;
  }

  async canFinalise(bridgeAddress: string, interactionNonce: bigint) {
    return await this.contract.canFinalise(bridgeAddress, interactionNonce);
  }

  async finalise(
    signer: Signer,
    bridgeAddress: string,
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    interactionNonce: bigint,
    auxInputData: bigint,
    options: SendTxOptions = {}
  ) {
    const contract = new Contract(
      this.contract.address,
      this.contract.interface,
      signer
    );
    const { gasLimit, gasPrice } = options;
    const tx = await contract.finalise(
      bridgeAddress,
      assetToArray(inputAssetA),
      assetToArray(inputAssetB),
      assetToArray(outputAssetA),
      assetToArray(outputAssetB),
      interactionNonce,
      auxInputData,
      {
        gasLimit,
        gasPrice,
      }
    );
    const receipt = await tx.wait();

    const parsedLogs = receipt.logs
      .filter((l: any) => l.address == contract.address)
      .map((l: any) => contract.interface.parseLog(l));

    const { outputValueA, outputValueB } = parsedLogs[0].args;

    return {
      outputValueA: BigInt(outputValueA.toString()),
      outputValueB: BigInt(outputValueB.toString()),
    };
  }

  async convert(
    signer: Signer,
    bridgeAddress: string,
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    totalInputValue: bigint,
    interactionNonce: bigint,
    auxInputData: bigint,
    options: SendTxOptions = {}
  ) {
    const contract = new Contract(
      this.contract.address,
      this.contract.interface,
      signer
    );
    const { gasLimit, gasPrice } = options;

    /* 1. In real life the rollup contract calls delegateCall on the defiBridgeProxy contract.

    The rollup contract has totalInputValue of inputAssetA and inputAssetB, it sends totalInputValue of both assets (if specified)  to the bridge contract.

    For a good developer UX we should do the same.

    */

    const tx = await contract.convert(
      bridgeAddress,
      assetToArray(inputAssetA),
      assetToArray(inputAssetB),
      assetToArray(outputAssetA),
      assetToArray(outputAssetB),
      totalInputValue,
      interactionNonce,
      auxInputData,
      { gasLimit, gasPrice }
    );
    const receipt = await tx.wait();

    const parsedLogs = receipt.logs
      .filter((l: any) => l.address == contract.address)
      .map((l: any) => contract.interface.parseLog(l));

    const { outputValueA, outputValueB, isAsync } = parsedLogs[0].args;

    return {
      isAsync,
      outputValueA: BigInt(outputValueA.toString()),
      outputValueB: BigInt(outputValueB.toString()),
    };
  }

  async preFundRollupWithTokens(signer: Signer, tokens: MyToken[]) {

    const WETH9Contract = new Contract(this.WETH9, WETH.abi, signer);
    const amount = 1n * 10n ** 21n;

    const depositTx = await WETH9Contract.deposit({ value: amount });
    await depositTx.wait();

    const approveWethTx = await WETH9Contract.approve(
      this.uniswapContract.address,
      amount
    );
    await approveWethTx.wait();

    for (const token of tokens) {
      const params = {
        tokenIn: this.WETH9,
        tokenOut: token.erc20Address,
        fee: 3000n,
        recipient: this.address,
        deadline: `0x${BigInt(Date.now() + 36000000).toString(16)}`,
        amountOut: token.amount,
        amountInMaximum: 1n * 10n ** 18n,
        sqrtPriceLimitX96: 0n,
      };

      const tempContract = await this.uniswapContract.connect(signer);

      const swapTx = await tempContract
        .exactOutputSingle(params)
        .catch(fixEthersStackTrace);
      await swapTx.wait();
    }
  }
}
