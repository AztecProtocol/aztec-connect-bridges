import { AssetValue } from "@aztec/barretenberg/asset";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { Web3Provider } from "@ethersproject/providers";
import "isomorphic-fetch";
import { createWeb3Provider } from "../aztec/provider";
import { AztecAsset } from "../bridge-data";

import { ERC4626BridgeData } from "../erc4626/erc4626-bridge-data";

export class EulerBridgeData extends ERC4626BridgeData {
  protected constructor(ethersProvider: Web3Provider) {
    super(ethersProvider);
  }

  static create(provider: EthereumProvider) {
    const ethersProvider = createWeb3Provider(provider);
    return new EulerBridgeData(ethersProvider);
  }

  async getAPR(yieldAsset: AztecAsset): Promise<number> {
    const underlyingAddress = await this.getAsset(yieldAsset.erc20Address);
    const result = await (
      await fetch("https://api.thegraph.com/subgraphs/name/euler-xyz/euler-mainnet", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          query: `
        query($id: String!) {
          asset(id: $id) {
            supplyAPY
          }
        }
      `,
          variables: {
            id: underlyingAddress.toString().toLowerCase(),
          },
        }),
      })
    ).json();

    return result.data.asset.supplyAPY / 10 ** 25;
  }

  /**
   * @notice Gets market size which in this case means the amount of underlying asset deposited to Euler
   * @param inputAssetA - The underlying asset
   * @param inputAssetB - ignored
   * @param outputAssetA - ignored
   * @param outputAssetB - ignored
   * @param auxData - ignored
   * @return The amount of the underlying asset deposited to Euler
   * @dev the returned value is displayed as totalSupply in Euler's UI
   */
  async getMarketSize(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: number,
  ): Promise<AssetValue[]> {
    const result = await (
      await fetch("https://api.thegraph.com/subgraphs/name/euler-xyz/euler-mainnet", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          query: `
        query($id: String!) {
          asset(id: $id) {
            totalBalances
          }
        }
      `,
          variables: {
            id: inputAssetA.erc20Address.toString().toLowerCase(),
          },
        }),
      })
    ).json();
    return [{ assetId: inputAssetA.id, value: BigInt(result.data.asset.totalBalances) }];
  }
}
