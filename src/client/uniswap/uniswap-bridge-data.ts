import {
  AssetValue,
  AuxDataConfig,
  AztecAsset,
  AztecAssetType,
  BridgeDataFieldGetters,
  SolidityType,
} from "../bridge-data";

import { EthAddress } from "@aztec/barretenberg/address";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { UniswapBridge, UniswapBridge__factory } from "../../../typechain-types";
import { createWeb3Provider } from "../aztec/provider";

export class UniswapBridgeData implements BridgeDataFieldGetters {
  private WETH = EthAddress.fromString("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");

  private constructor(private uniswapBridge: UniswapBridge) {}

  static create(provider: EthereumProvider, uniswapBridgeAddress: EthAddress) {
    const ethersProvider = createWeb3Provider(provider);
    const uniswapBridge = UniswapBridge__factory.connect(uniswapBridgeAddress.toString(), ethersProvider);
    return new UniswapBridgeData(uniswapBridge);
  }

  public auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: "Encoded swap path and min price",
    },
  ];

  // Uniswap bridge contract is stateless
  async getInteractionPresentValue(interactionNonce: bigint): Promise<AssetValue[]> {
    return [];
  }

  async getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    inputValue: bigint,
  ): Promise<bigint[]> {
    const inputAddr = inputAssetA.assetType === AztecAssetType.ERC20 ? inputAssetA.erc20Address : this.WETH;
    const outputAddr = outputAssetA.assetType === AztecAssetType.ERC20 ? outputAssetA.erc20Address : this.WETH;

    const quote = await this.uniswapBridge.callStatic.quote(
      inputValue,
      inputAddr.toString(),
      auxData,
      outputAddr.toString(),
    );

    return [quote.toBigInt()];
  }
}
