import { Contract, ContractFactory, Signer } from "ethers";

import abi from "./artifacts/contracts/MockRollupProcessor.sol/MockRollupProcessor.json";

import ISwapRouter from "./artifacts/contracts/interfaces/ISwapRouter.sol/ISwapRouter.json";
import WETH from "./artifacts/contracts/interfaces/IWETH.sol/WETH.json";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import { Curve } from "./curve";
import {
  AztecAsset,
  SendTxOptions,
  assetToArray,
} from "./utils";

export interface TestToken {
  amount: bigint;
  erc20Address: string;
  name: string;
}

export class RollupProcessor {
  private contract: Contract;
  private WETH9: string;
  private wethContract: Contract;

  constructor(public address: string, signer: Signer) {
    this.contract = new Contract(this.address, abi.abi, signer);
    this.WETH9 = "0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2";

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

    const results = parsedLogs.map((log: any) => {
      return {
        outputValueA: log.args.outputValueA.toBigInt(),
        outputValueB: log.args.outputValueB.toBigInt(),
        isAsync: log.args.isAsync,
      };
    });

    return {
      results,
      gasUsed: receipt.gasUsed.toBigInt(),
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
      gasUsed: receipt.gasUsed.toBigInt(),
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
    to?: string,
    amountInMaximum = 1n * 10n ** 21n
  ) {
    const swapper = new Curve(signer);
    await swapper.init();
    await swapper.swap(to ?? this.address, token, amountInMaximum);
  }
}
