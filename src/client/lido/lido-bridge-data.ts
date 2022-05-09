import { AssetValue, AuxDataConfig, AztecAsset, SolidityType, AztecAssetType, YieldBridgeData } from '../bridge-data';

import {
  IWstETH,
  ILidoOracle,
  ICurvePool,
  IWstETH__factory,
  ILidoOracle__factory,
  ICurvePool__factory,
} from '../../../typechain-types';
import { EthereumProvider } from '../aztec/provider/ethereum_provider';
import { createWeb3Provider } from '../aztec/provider';

export class LidoBridgeData implements YieldBridgeData {
  public scalingFactor: bigint = 1n * 10n ** 18n;

  private constructor(
    private wstETHContract: IWstETH,
    private lidoOracleContract: ILidoOracle,
    private curvePoolContract: ICurvePool,
  ) {}

  static create(
    provider: EthereumProvider,
    wstEthAddress: string,
    lidoOracleAddress: string,
    curvePoolAddress: string,
  ) {
    const ethersProvider = createWeb3Provider(provider);
    const wstEthContract = IWstETH__factory.connect(wstEthAddress, ethersProvider);
    const lidoContract = ILidoOracle__factory.connect(lidoOracleAddress, ethersProvider);
    const curvePoolContract = ICurvePool__factory.connect(curvePoolAddress, ethersProvider);
    return new LidoBridgeData(wstEthContract, lidoContract, curvePoolContract);
  }

  // Unused
  public auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: 'Not Used',
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
      const curveMinOutput = await this.curvePoolContract.get_dy(0, 1, inputValue);
      if (curveMinOutput.toBigInt() > inputValue) {
        return [curveMinOutput.toBigInt()];
      } else {
        return [inputValue];
      }
    }

    // wstETH -> ETH
    if (inputAssetA.assetType == AztecAssetType.ERC20) {
      const stETHBalance = await this.wstETHContract.getStETHByWstETH(inputValue);
      const ETHBalance = await this.curvePoolContract.get_dy(1, 0, stETHBalance);
      return [ETHBalance.toBigInt()];
    }
    return [0n];
  }
  async getExpectedYearlyOuput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    precision: bigint,
  ): Promise<bigint[]> {
    const YEAR = 60n * 60n * 24n * 365n;
    if (outputAssetA.assetType === AztecAssetType.ETH) {
      const { postTotalPooledEther, preTotalPooledEther, timeElapsed } =
        await this.lidoOracleContract.getLastCompletedReportDelta();

      const scaledAPR =
        ((postTotalPooledEther.toBigInt() - preTotalPooledEther.toBigInt()) * YEAR * this.scalingFactor) /
        (preTotalPooledEther.toBigInt() * timeElapsed.toBigInt());
      const stETHBalance = await this.wstETHContract.getStETHByWstETH(precision);
      const ETHBalance = (await this.curvePoolContract.get_dy(1, 0, stETHBalance)).toBigInt();
      const expectedYearlyOutputETH = ETHBalance + (ETHBalance * scaledAPR) / this.scalingFactor;

      return [expectedYearlyOutputETH];
    }
    return [0n];
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
