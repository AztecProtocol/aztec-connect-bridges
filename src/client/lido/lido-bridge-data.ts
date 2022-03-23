import { AssetValue, AuxDataConfig, AztecAsset, SolidityType, BridgeData, AztecAssetType } from '../bridge-data';

import { IWstETH, RollupProcessor, ICurvePool } from '../../../typechain-types';

function rootNth(val: bigint, k?: bigint): bigint {
  if (!k) k = 2n;
  let o = 0n; // old approx value
  let x = val;
  let limit = 1000;

  while (x ** k !== k && x !== o && --limit) {
    o = x;
    x = ((k - 1n) * x + val / x ** (k - 1n)) / k;
  }

  return x;
}

export class LidoBridgeData implements BridgeData {
  private wstETHContract: IWstETH;
  private curvePoolContract: ICurvePool;
  public scalingFactor: bigint = 1n * 10n ** 18n;

  constructor(wstETHContract: IWstETH, curvePoolContract: ICurvePool) {
    this.wstETHContract = wstETHContract;
    this.curvePoolContract = curvePoolContract;
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
    const gwei = BigInt(10n ** 9n);
    const depositContractBalance = (
      await this.curvePoolContract.provider.getBalance('0x00000000219ab540356cBB839Cbe05303d7705Fa')
    ).toBigInt();
    const depositContractBalanceGwei = depositContractBalance / gwei;
    const EPOCHS_PER_YEAR = 82180n;
    // precision is in wei, the beacon chain deals in gwei....

    const precisionGwei = precision / gwei;

    const baseReward = (EPOCHS_PER_YEAR * 512n * this.scalingFactor) / rootNth(depositContractBalanceGwei);

    const multiplier = ((precisionGwei * 4n * baseReward) / 32n) * 10n ** 9n;

    return [multiplier / this.scalingFactor];
  }
}
