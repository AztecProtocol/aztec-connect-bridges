import { EthAddress } from "@aztec/barretenberg/address";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { DataProvider__factory } from "../../../../typechain-types";
import { DataProvider } from "../../../typechain-types";
import { createWeb3Provider } from "../provider";

export interface AssetData {
  assetAddress: EthAddress;
  assetId: number;
  label: string;
}

export interface BridgeData {
  bridgeAddress: EthAddress;
  bridgeAddressId: number;
  label: string;
}

export class DataProviderWrapper {
  private constructor(private dataProvider: DataProvider) {}

  static create(provider: EthereumProvider, dataProviderAddress: EthAddress) {
    const ethersProvider = createWeb3Provider(provider);
    return new DataProviderWrapper(DataProvider__factory.connect(dataProviderAddress.toString(), ethersProvider));
  }

  async getBridgeByName(name: string): Promise<BridgeData> {
    const bd = await this.dataProvider.getBridge(name);
    return {
      bridgeAddress: EthAddress.fromString(bd.bridgeAddress),
      bridgeAddressId: bd.bridgeAddressId.toNumber(),
      label: bd.label,
    };
  }

  async getBridgeById(bridgeAddressId: number): Promise<BridgeData> {
    const bd = await this.dataProvider.getBridge(bridgeAddressId);
    return {
      bridgeAddress: EthAddress.fromString(bd.bridgeAddress),
      bridgeAddressId: bd.bridgeAddressId.toNumber(),
      label: bd.label,
    };
  }

  async getAssetByName(name: string): Promise<AssetData> {
    const ad = await this.dataProvider.getAsset(name);
    return {
      assetAddress: EthAddress.fromString(ad.assetAddress),
      assetId: ad.assetId.toNumber(),
      label: ad.label,
    };
  }

  async getAssetById(assetId: number): Promise<AssetData> {
    const ad = await this.dataProvider.getAsset(assetId);
    return {
      assetAddress: EthAddress.fromString(ad.assetAddress),
      assetId: ad.assetId.toNumber(),
      label: ad.label,
    };
  }

  async getRollupProvider(): Promise<EthAddress> {
    return EthAddress.fromString(await this.dataProvider.ROLLUP_PROCESSOR());
  }
}
