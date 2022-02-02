import { Contract, ContractFactory, Signer } from "ethers";
import { assetToArray, AztecAssetType, AztecAsset, SendTxOptions } from "./utils";
import Element from "./artifacts/contracts/bridges/ElementFinance/ElementBridge.sol/ElementBridge.json";


export class ElementBridge {
  private contract: Contract;

  constructor(public address: string, signer: Signer) {
    this.contract = new Contract(this.address, Element.abi, signer);
  }

  static async deploy(signer: Signer, args: any[]) {
    const factory = new ContractFactory(Element.abi, Element.bytecode, signer);
    const contract = await factory.deploy(...args);
    return new ElementBridge(contract.address, signer);
  }

  async canFinalise(interactionNonce: bigint) {
    return await this.contract.canFinalise(interactionNonce);
  }

  async registerConvergentPoolAddress(
    signer: Signer,
    wrappedPositionAddress: string,
    poolAddress: string,
    expiry: number,
    options: SendTxOptions = {}
  ) {
    const contract = new Contract(
      this.contract.address,
      this.contract.interface,
      signer
    );
    const tx = await contract.registerConvergentPoolAddress(
      wrappedPositionAddress,
      poolAddress,
      expiry
    );
    await tx.wait();
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
      assetToArray(inputAssetA),
      assetToArray(inputAssetB),
      assetToArray(outputAssetA),
      assetToArray(outputAssetB),
      interactionNonce,
      auxInputData,
      { gasLimit, gasPrice }
    );
    const receipt = await tx.wait();

    // const parsedLogs = receipt.logs
    //   .filter((l: any) => l.address == contract.address)
    //   .map((l: any) => contract.interface.parseLog(l));

    // const { outputValueA, outputValueB } = parsedLogs[0].args;

    return {
      outputValueA: 0n,
      outputValueB: 0n,
      gasUsed: receipt.gasUsed.toBigInt(),
    };
  }
}
