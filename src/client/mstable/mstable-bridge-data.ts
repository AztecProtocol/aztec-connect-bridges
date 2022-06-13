import fetch from 'node-fetch';
import { AuxDataConfig, AztecAsset, SolidityType, BridgeDataFieldGetters } from '../bridge-data';
import {
  IMStableSavingsContract,
  IMStableAsset,
  IMStableSavingsContract__factory,
  IMStableAsset__factory,
} from '../../../typechain-types';
import { EthereumProvider } from '@aztec/barretenberg/blockchain';
import { createWeb3Provider } from '../aztec/provider';
import { EthAddress } from '@aztec/barretenberg/address';

export class MStableBridgeData implements BridgeDataFieldGetters {
  private dai = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

  public scalingFactor = 1000000000n;

  private constructor(
    private mStableSavingsContract: IMStableSavingsContract,
    private mStableAssetContract: IMStableAsset,
  ) {}

  static create(provider: EthereumProvider, mStableSavingsAddress: EthAddress, mStableAssetAddress: EthAddress) {
    const ethersProvider = createWeb3Provider(provider);
    const savingsContract = IMStableSavingsContract__factory.connect(mStableSavingsAddress.toString(), ethersProvider);
    const assetContract = IMStableAsset__factory.connect(mStableAssetAddress.toString(), ethersProvider);
    return new MStableBridgeData(savingsContract, assetContract);
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
