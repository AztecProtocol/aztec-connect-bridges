import { AuxDataConfig, AztecAsset, BridgeDataFieldGetters, SolidityType } from "../bridge-data";
import { AssetValue } from "@aztec/barretenberg/asset";

export class ExampleBridgeData implements BridgeDataFieldGetters {
  constructor() {}

  // @dev This function should be implemented for stateful bridges. It should return an array of AssetValue's
  // @dev which define how much a given interaction is worth in terms of Aztec asset ids.
  // @param interactionNonce the nonce to return the value for

  async getInteractionPresentValue(interactionNonce: number): Promise<AssetValue[]> {
    return [
      {
        assetId: 1,
        value: 1000n,
      },
    ];
  }

  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<number[]> {
    return [0];
  }

  public auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: "Not Used",
    },
  ];

  async getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: number,
    inputValue: bigint,
  ): Promise<bigint[]> {
    return [100n, 0n];
  }

  async getMarketSize(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: number,
  ): Promise<AssetValue[]> {
    return [{ assetId: 0, value: 100n }];
  }
}
