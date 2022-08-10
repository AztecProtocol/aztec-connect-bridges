import { EthAddress } from "@aztec/barretenberg/address";
import { JsonRpcProvider } from "@ethersproject/providers";
import { IERC20__factory, IERC4626__factory } from "../../../typechain-types";
import {
  AssetValue,
  AuxDataConfig,
  AztecAsset,
  AztecAssetType,
  BridgeDataFieldGetters,
  SolidityType,
} from "../bridge-data";

export class ERC4626BridgeData implements BridgeDataFieldGetters {
  readonly WETH = EthAddress.fromString("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");

  private constructor(private ethersProvider: JsonRpcProvider) {}

  // static create(provider: EthereumProvider) {
  static create() {
    // const ethersProvider = createWeb3Provider(provider);
    const ethersProvider = new JsonRpcProvider("https://mainnet.infura.io/v3/9928b52099854248b3a096be07a6b23c");
    return new ERC4626BridgeData(ethersProvider);
  }

  auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: "AuxData determine whether issue (0) or redeem flow (1) is executed",
    },
  ];

  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<bigint[]> {
    let vault = IERC4626__factory.connect(outputAssetA.erc20Address.toString(), this.ethersProvider);
    try {
      let vaultAsset = EthAddress.fromString(await vault.asset());
      if (vaultAsset.equals(inputAssetA.erc20Address)) {
        return [0n];
      } else {
        throw "Address of vault's asset isn't equal to inputAssetA.erc20address";
      }
    } catch {}

    vault = IERC4626__factory.connect(inputAssetA.erc20Address.toString(), this.ethersProvider);
    try {
      let vaultAsset = EthAddress.fromString(await vault.asset());
      if (vaultAsset.equals(outputAssetA.erc20Address)) {
        return [1n];
      } else {
        throw "Address of vault's asset isn't equal to outputAssetA.erc20address";
      }
    } catch {
      throw "Neither input nor output asset is a share of an ERC4626 vault";
    }
  }

  async getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    inputValue: bigint,
  ): Promise<bigint[]> {
    if (auxData === 0n) {
      // Issuing
      const shareAddress = outputAssetA.erc20Address;
      const vault = IERC4626__factory.connect(shareAddress.toString(), this.ethersProvider);
      const amountOut = await vault.previewDeposit(inputValue);
      return [amountOut.toBigInt()];
    } else if (auxData === 1n) {
      // Redeeming
      const shareAddress = inputAssetA.erc20Address;
      const vault = IERC4626__factory.connect(shareAddress.toString(), this.ethersProvider);
      const amountOut = await vault.previewRedeem(inputValue);
      return [amountOut.toBigInt()];
    } else {
      throw "Invalid auxData";
    }
  }

  async getMarketSize(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
  ): Promise<AssetValue[]> {
    let shareAddress;
    let asset;
    if (auxData === 0n) {
      // Issuing
      shareAddress = outputAssetA.erc20Address;
      asset = inputAssetA;
    } else if (auxData === 1n) {
      // Redeeming
      shareAddress = inputAssetA.erc20Address;
      asset = outputAssetA;
    } else {
      throw "Invalid auxData";
    }

    const assetAddress = asset.assetType === AztecAssetType.ETH ? this.WETH : asset.erc20Address;

    const marketSize = await IERC20__factory.connect(assetAddress.toString(), this.ethersProvider).balanceOf(
      shareAddress.toString(),
    );
    return [
      {
        assetId: asset.id,
        amount: marketSize.toBigInt(),
      },
    ];
  }
}
