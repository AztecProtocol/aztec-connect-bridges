import { Provider, Web3Provider } from "@ethersproject/providers";
import { Contract, ContractFactory, ethers, Signer } from "ethers";

import abi from "./artifacts/contracts/MockRollupProcessor.sol/MockRollupProcessor.json";

import ISwapRouter from "./artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import WETH from "./artifacts/contracts/interfaces/IWETH.sol/WETH.json";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import { Uniswap } from "./uniswap";
import { Curve } from "./curve";

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

export interface TestToken {
  amount: bigint;
  erc20Address: string;
  name: string;
}

export class RollupProcessor {
  private contract: Contract;
  private uniswapContract: Contract;
  private WETH9: string;
  private wethContract: Contract;

  constructor(public address: string, signer: Signer) {
    this.contract = new Contract(this.address, abi.abi, signer);
    this.WETH9 = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";

    this.uniswapContract = new Contract(
      "0xe592427a0aece92de3edee1f18e0157c05861564",
      ISwapRouter.abi,
      signer
    );

    this.wethContract = new Contract(this.WETH9, WETH.abi, signer);
  }

  static async deploy(signer: Signer, args: any[]) {
    const factory = new ContractFactory(abi.abi, abi.bytecode, signer);
    const contract = await factory.deploy(...args);
    return new RollupProcessor(contract.address, signer);
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

  async processAsyncDefiInteraction(
    signer: Signer,
    interactionNonce: bigint,
    options: SendTxOptions = {}
  ) {
    const contract = new Contract(
      this.contract.address,
      this.contract.interface,
      signer
    );
    const { gasLimit, gasPrice } = options;
    const tx = await contract.processAsyncDeFiInteraction(interactionNonce, {
      gasLimit,
      gasPrice,
    });
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

  async getWethBalance() {
    const currentBalance = await this.wethContract.balanceOf(this.address);
    return currentBalance.toBigInt();
  }

  async getTokenBalance(address: string, signer: Signer) {
    const tokenContract = new Contract(address, ERC20.abi, signer);
    const currentBalance = await tokenContract.balanceOf(this.address);
    return currentBalance.toBigInt();
  }

  async preFundContractWithToken(
    signer: Signer,
    token: TestToken,
    to?: string
  ) {
    const amount = 1n * 10n ** 21n;

    if (
      token.erc20Address.toLowerCase() ===
      this.wethContract.address.toLowerCase()
    ) {
      return;
    }

    const swapper = new Curve(signer);
    await swapper.init();
    await swapper.swap(to ?? this.address, token, amount);
    console.log(
      `After swap, contract now has ${await this.getWethBalance()} WETH and ${await this.getTokenBalance(
        token.erc20Address,
        signer
      )} ${token.name}`
    );
  }
}
