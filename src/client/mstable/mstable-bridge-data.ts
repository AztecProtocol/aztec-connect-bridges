import fetch from 'node-fetch';
import { AuxDataConfig, AztecAsset, SolidityType, BridgeDataFieldGetters } from '../bridge-data';
import { MStableBridge, IRollupProcessor, IMStableSavingsContract, IMStableAsset } from '../../../typechain-types';

export class MStableBridgeData implements BridgeDataFieldGetters {
  private mStableBridgeContract: MStableBridge;
  private rollupContract: IRollupProcessor;
  private mStableSavingsContract: IMStableSavingsContract;
  private mStableAssetContract: IMStableAsset;
  private imUSD = '0x30647a72Dc82d7Fbb1123EA74716aB8A317Eac19';
  private dai = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

  public scalingFactor = 1000000000n;

  constructor(
    mStableBridge: MStableBridge,
    mStableSavings: IMStableSavingsContract,
    rollupContract: IRollupProcessor,
    mStableAsset: IMStableAsset,
  ) {
    this.mStableBridgeContract = mStableBridge;
    this.rollupContract = rollupContract;
    this.mStableSavingsContract = mStableSavings;
    this.mStableAssetContract = mStableAsset;
  }

  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<bigint[]> {
    return await [50n];
  }

  public auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: 'Unix Timestamp of the tranch expiry',
    },
  ];

  async getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    precision: bigint,
  ): Promise<bigint[]> {
    if (inputAssetA.erc20Address === this.dai) {
      const mintOutput = (await this.mStableAssetContract.getMintOutput(this.dai, precision)).toBigInt();
      const exchangeRate = (await this.mStableSavingsContract.exchangeRate()).toBigInt();
      return [(mintOutput * this.scalingFactor) / exchangeRate];
    } else {
      const exchangeRate = (await this.mStableSavingsContract.exchangeRate()).toBigInt();
      const redeemOutput = (await this.mStableAssetContract.getRedeemOutput(this.dai, precision)).toBigInt();
      return [exchangeRate * redeemOutput];
    }
  }

  async getExpectedYield(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    precision: bigint,
  ): Promise<number[]> {
    if (outputAssetA.erc20Address === this.dai) {
      // input asset is IMUSD
      const res = await fetch('https://api.thegraph.com/subgraphs/name/mstable/mstable-protocol', {
        method: 'POST',
        body: JSON.stringify({
          query: 'query MyQuery {\n  savingsContracts {\n    dailyAPY\n  }\n}\n',
          variables: null,
          operationName: 'MyQuery',
        }),
      }).then(response => response.json());

      return [Number(res.data.savingsContracts[2].dailyAPY)];
    }
    return [];
  }
}
