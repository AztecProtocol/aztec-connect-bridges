import { EthAddress } from "@aztec/barretenberg/address";
import { AssetValue } from "@aztec/barretenberg/asset";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { Web3Provider } from "@ethersproject/providers";
import "isomorphic-fetch";
import { ICERC20__factory, ICompoundERC4626__factory, IERC20__factory } from "../../../typechain-types";
import { createWeb3Provider } from "../aztec/provider";
import { AztecAsset, AztecAssetType } from "../bridge-data";

import { ERC4626BridgeData } from "../erc4626/erc4626-bridge-data";

export class CompoundBridgeData extends ERC4626BridgeData {
  protected constructor(ethersProvider: Web3Provider) {
    super(ethersProvider);
  }

  static create(provider: EthereumProvider) {
    const ethersProvider = createWeb3Provider(provider);
    return new CompoundBridgeData(ethersProvider);
  }

  async getAPR(yieldAsset: AztecAsset): Promise<number> {
    // Not taking into account how the deposited funds will change the yield
    // The approximate number of blocks per year that is assumed by the interest rate model

    const blocksPerYear = 2102400;

    // To get the cToken first call cToken on the wrapper contract
    const cTokenAddress = await this.getCToken(yieldAsset.erc20Address);
    const cToken = ICERC20__factory.connect(cTokenAddress.toString(), this.ethersProvider);

    const supplyRatePerBlock = await cToken.supplyRatePerBlock();
    return supplyRatePerBlock.mul(blocksPerYear).toNumber() / 10 ** 16;
  }

  async getMarketSize(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: number,
  ): Promise<AssetValue[]> {
    let cTokenAddress;
    let underlyingAsset;
    if (auxData === 0) {
      // Minting
      cTokenAddress = this.getCToken(outputAssetA.erc20Address);
      underlyingAsset = inputAssetA;
    } else if (auxData === 1) {
      // Redeeming
      cTokenAddress = this.getCToken(inputAssetA.erc20Address);
      underlyingAsset = outputAssetA;
    } else {
      throw "Invalid auxData";
    }

    let marketSize;
    if (underlyingAsset.assetType === AztecAssetType.ETH) {
      marketSize = await this.ethersProvider.getBalance(cTokenAddress.toString());
    } else {
      marketSize = await IERC20__factory.connect(
        underlyingAsset.erc20Address.toString(),
        this.ethersProvider,
      ).balanceOf(cTokenAddress.toString());
    }
    return [
      {
        assetId: underlyingAsset.id,
        value: marketSize.toBigInt(),
      },
    ];
  }

  private async getCToken(shareAddress: EthAddress): Promise<EthAddress> {
    const share = ICompoundERC4626__factory.connect(shareAddress.toString(), this.ethersProvider);
    return EthAddress.fromString(await share.cToken());
  }
}
