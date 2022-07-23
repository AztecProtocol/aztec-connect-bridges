import {
  AssetValue,
  AuxDataConfig,
  AztecAsset,
  SolidityType,
  AztecAssetType,
  BridgeDataFieldGetters,
} from "../bridge-data";

import {
  IWstETH,
  ILidoOracle,
  ICurvePool,
  IWstETH__factory,
  ILidoOracle__factory,
  ICurvePool__factory,
} from "../../../typechain-types";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { createWeb3Provider } from "../aztec/provider";
import { EthAddress } from "@aztec/barretenberg/address";

export class LidoBridgeData implements BridgeDataFieldGetters {
  public scalingFactor: bigint = 1n * 10n ** 18n;

  private constructor(
    private wstETHContract: IWstETH,
    private lidoOracleContract: ILidoOracle,
    private curvePoolContract: ICurvePool,
  ) {}

  static create(
    provider: EthereumProvider,
    wstEthAddress: EthAddress,
    lidoOracleAddress: EthAddress,
    curvePoolAddress: EthAddress,
  ) {
    const ethersProvider = createWeb3Provider(provider);
    const wstEthContract = IWstETH__factory.connect(wstEthAddress.toString(), ethersProvider);
    const lidoContract = ILidoOracle__factory.connect(lidoOracleAddress.toString(), ethersProvider);
    const curvePoolContract = ICurvePool__factory.connect(curvePoolAddress.toString(), ethersProvider);
    return new LidoBridgeData(wstEthContract, lidoContract, curvePoolContract);
  }

  // Unused
  public auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: "Not Used",
    },
  ];

  // Lido bridge contract is stateless
  async getInteractionPresentValue(interactionNonce: bigint): Promise<AssetValue[]> {
    return [];
  }

  // Not applicable
  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<bigint[]> {
    return [0n];
  }

  async getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    inputValue: bigint,
  ): Promise<bigint[]> {
    // ETH -> wstETH
    if (inputAssetA.assetType == AztecAssetType.ETH) {
      // Assume ETH -> stETh 1:1 (there will be a tiny diff because rounding down)
      const wstETHBalance = await this.wstETHContract.getWstETHByStETH(inputValue);
      return [wstETHBalance.toBigInt()];
    }

    // wstETH -> ETH
    if (inputAssetA.assetType == AztecAssetType.ERC20) {
      const stETHBalance = await this.wstETHContract.getStETHByWstETH(inputValue);
      const ETHBalance = await this.curvePoolContract.get_dy(1, 0, stETHBalance);
      return [ETHBalance.toBigInt()];
    }
    return [0n];
  }
  async getAPR(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    inputValue: bigint,
  ): Promise<number[]> {
    const YEAR = 60n * 60n * 24n * 365n;
    if (outputAssetA.assetType === AztecAssetType.ETH) {
      const { postTotalPooledEther, preTotalPooledEther, timeElapsed } =
        await this.lidoOracleContract.getLastCompletedReportDelta();

      const scaledAPR =
        ((postTotalPooledEther.toBigInt() - preTotalPooledEther.toBigInt()) * YEAR * this.scalingFactor) /
        (preTotalPooledEther.toBigInt() * timeElapsed.toBigInt());

      return [Number(scaledAPR / (this.scalingFactor / 10000n)) / 100];
    }
    return [0];
  }

  async getMarketSize(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
  ): Promise<AssetValue[]> {
    const { postTotalPooledEther } = await this.lidoOracleContract.getLastCompletedReportDelta();
    return [
      {
        assetId: inputAssetA.id,
        amount: postTotalPooledEther.toBigInt(),
      },
    ];
  }
}
