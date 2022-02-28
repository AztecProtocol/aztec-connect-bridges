import {
  AaveLendingBridge,
  ILendingPoolAddressesProvider__factory,
  ILendingPool__factory,
  RollupProcessor,
} from '../../../typechain-types';
import { AssetValue, AuxDataConfig, AztecAsset, BridgeData, SolidityType } from '../bridge-data';

export class AaveLendingBridgeData implements BridgeData {
  private aaveLendingBridge: AaveLendingBridge;
  private rollupProcessor: RollupProcessor;

  constructor(aaveLendingBridge: AaveLendingBridge, rollupProcessor: RollupProcessor) {
    this.aaveLendingBridge = aaveLendingBridge;
    this.rollupProcessor = rollupProcessor;
  }

  /// Asset values do not depend on the `interactionNonce`
  async getInteractionPresentValue(interactionNonce: bigint): Promise<AssetValue[]> {
    return [];
  }

  /// No aux data needed for the lending bridge
  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<bigint[]> {
    return [0n];
  }

  public auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: 'Not Used',
    },
  ];

  async getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    inputValue: bigint,
  ): Promise<bigint[]> {
    // Need some logic to handle what way we are going
    // Thinking that the easiest would be just to simulate?
    // Seems like the easiests. Just emulating the convert call directly

    const { outputValueA, outputValueB } = await this.aaveLendingBridge.callStatic.convert(
      inputAssetA,
      inputAssetB,
      outputAssetA,
      outputAssetB,
      inputValue,
      0,
      auxData,
      { from: this.rollupProcessor.address },
    );

    return [outputValueA.toBigInt(), outputValueB.toBigInt()];
  }

  async getExpectedYearlyOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    inputValue: bigint,
  ): Promise<bigint[]> {
    // Note: This one may be a little odd if exiting?
    // Assume only input here

    // Should essentially just pull liquidity rate from the lending pool
    const addressesProvider = ILendingPoolAddressesProvider__factory.connect(
      await this.aaveLendingBridge.ADDRESSES_PROVIDER(),
      this.aaveLendingBridge.signer,
    );

    const lendingPool = ILendingPool__factory.connect(
      await addressesProvider.getLendingPool(),
      this.aaveLendingBridge.signer,
    );

    const reserveData = await lendingPool.getReserveData(inputAssetA.erc20Address);

    return [100n, 0n];
  }

  async getMarketSize(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
  ): Promise<AssetValue[]> {
    return [{ assetId: 0n, amount: 100n }];
  }
}
