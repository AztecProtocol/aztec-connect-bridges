import axios from 'axios';
import { AuxDataConfig, AztecAsset, SolidityType } from '../bridge-data';
import {
  IMStableSavingsContract,
  IMStableAsset,
  IMStableSavingsContract__factory,
  IMStableAsset__factory,
} from '../../../typechain-types';
import { EthereumProvider } from '../aztec/provider/ethereum_provider';
import { createWeb3Provider } from '../aztec/provider';

export type BatchSwapStep = {
  poolId: string;
  assetInIndex: number;
  assetOutIndex: number;
  amount: string;
  userData: string;
};

export enum SwapType {
  SwapExactIn,
  SwapExactOut,
}

export type FundManagement = {
  sender: string;
  recipient: string;
  fromInternalBalance: boolean;
  toInternalBalance: boolean;
};

export class MStableBridgeData {
  private dai = '0x6B175474E89094C44Da98b954EedeAC495271d0F';

  public scalingFactor = 1000000000n;

  private constructor(
    private mStableSavingsContract: IMStableSavingsContract,
    private mStableAssetContract: IMStableAsset,
  ) {}

  static create(provider: EthereumProvider, mStableSavingsAddress: string, mStableAssetAddress: string) {
    const ethersProvider = createWeb3Provider(provider);
    const savingsContract = IMStableSavingsContract__factory.connect(mStableSavingsAddress, ethersProvider);
    const assetContract = IMStableAsset__factory.connect(mStableAssetAddress, ethersProvider);
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

  async getExpectedYearlyOuput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    precision: bigint,
  ): Promise<bigint[]> {
    if (outputAssetA.erc20Address === this.dai) {
      // input asset is IMUSD
      let res = await axios('https://api.mstable.org/pools');
      const scaledApy = BigInt(Math.floor(res.data.pools[2].apy * Number(this.scalingFactor))) / 100n;
      const exchangeRate = (await this.mStableSavingsContract.exchangeRate()).toBigInt();
      const redeemOutput = (await this.mStableAssetContract.getRedeemOutput(this.dai, precision)).toBigInt();
      const expectedYearlyOutput = exchangeRate * (redeemOutput + (redeemOutput * scaledApy) / this.scalingFactor);

      return [expectedYearlyOutput];
    }
    return [];
  }
}
