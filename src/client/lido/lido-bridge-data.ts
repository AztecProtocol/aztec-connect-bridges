import { AssetValue, AuxDataConfig, AztecAsset, SolidityType, BridgeData, AztecAssetType } from '../bridge-data';

import { IWstETH, RollupProcessor, ICurvePool } from '../../../typechain-types';

export class LidoBridgeData implements BridgeData {
  private wstETHContract: IWstETH;
  private curvePoolContract: ICurvePool;

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
}
