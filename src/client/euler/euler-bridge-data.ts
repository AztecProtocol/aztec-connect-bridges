import { EthAddress } from "@aztec/barretenberg/address";
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
}
