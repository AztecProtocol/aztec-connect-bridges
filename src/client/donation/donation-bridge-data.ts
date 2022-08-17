import { AssetValue } from "@aztec/barretenberg/asset";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { Web3Provider } from "@ethersproject/providers";
import { IRollupProcessor, IRollupProcessor__factory } from "../../../typechain-types";
import { createWeb3Provider } from "../aztec/provider";
import { AuxDataConfig, AztecAsset, AztecAssetType, BridgeDataFieldGetters, SolidityType } from "../bridge-data";

export class DonationBridgeData implements BridgeDataFieldGetters {
  private constructor(private ethersProvider: Web3Provider, private rollupProcessor: IRollupProcessor) {}

  static create(provider: EthereumProvider) {
    const ethersProvider = createWeb3Provider(provider);
    return new DonationBridgeData(
      createWeb3Provider(provider),
      IRollupProcessor__factory.connect("0xFF1F2B4ADb9dF6FC8eAFecDcbF96A2B351680455", ethersProvider),
    );
  }

  auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: "AuxData determine whether who will receive the donation",
    },
  ];

  // Not applicable
  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<number[]> {
    return [0];
  }

  async getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: number,
    inputValue: bigint,
  ): Promise<bigint[]> {
    if (
      auxData > 0n &&
      (inputAssetA.assetType == AztecAssetType.ETH || inputAssetA.assetType == AztecAssetType.ERC20)
    ) {
      return [0n];
    } else {
      throw "Invalid auxData";
    }
  }

  async getAPR(yieldAsset: AztecAsset): Promise<number> {
    return 0;
  }

  async getMarketSize(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: number,
  ): Promise<AssetValue[]> {
    return [
      {
        assetId: inputAssetA.id,
        value: 0n,
      },
    ];
  }
}
