import { EthAddress } from "@aztec/barretenberg/address";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { Web3Provider } from "@ethersproject/providers";
import { BigNumber } from "ethers";
import {
  ICERC20__factory,
  IComptroller,
  IComptroller__factory,
  IERC20__factory,
  IRollupProcessor,
  IRollupProcessor__factory,
} from "../../../typechain-types";
import { createWeb3Provider } from "../aztec/provider";
import {
  AssetValue,
  AuxDataConfig,
  AztecAsset,
  AztecAssetType,
  BridgeDataFieldGetters,
  SolidityType,
} from "../bridge-data";

export class CompoundBridgeData implements BridgeDataFieldGetters {
  readonly expScale = 10n ** 18n;

  allMarkets?: EthAddress[];

  private constructor(
    private ethersProvider: Web3Provider,
    private comptroller: IComptroller,
    private rollupProcessor: IRollupProcessor,
  ) {}

  static create(provider: EthereumProvider) {
    const ethersProvider = createWeb3Provider(provider);
    return new CompoundBridgeData(
      createWeb3Provider(provider),
      IComptroller__factory.connect("0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B", ethersProvider),
      IRollupProcessor__factory.connect("0xFF1F2B4ADb9dF6FC8eAFecDcbF96A2B351680455", ethersProvider),
    );
  }

  auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: "AuxData determine whether mint (0) or redeem flow (1) is executed",
    },
  ];

  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<bigint[]> {
    const allMarkets = await this.getAllMarkets();

    if (!(await this.isSupportedAsset(inputAssetA))) {
      throw "inputAssetA not supported";
    }
    if (!(await this.isSupportedAsset(outputAssetA))) {
      throw "outputAssetA not supported";
    }

    if (allMarkets.some(addr => addr.equals(inputAssetA.erc20Address))) {
      return [1n];
    } else if (allMarkets.some(addr => addr.equals(outputAssetA.erc20Address))) {
      return [0n];
    } else {
      throw "Invalid input and/or output asset";
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
      // Minting
      const cToken = ICERC20__factory.connect(outputAssetA.erc20Address.toString(), this.ethersProvider);
      const exchangeRateStored = await cToken.exchangeRateStored();
      return [BigNumber.from(inputValue).mul(this.expScale).div(exchangeRateStored).toBigInt()];
    } else if (auxData === 1n) {
      // Redeeming
      const cToken = ICERC20__factory.connect(inputAssetA.erc20Address.toString(), this.ethersProvider);
      const exchangeRateStored = await cToken.exchangeRateStored();
      return [BigNumber.from(inputValue).mul(exchangeRateStored).div(this.expScale).toBigInt()];
    } else {
      throw "Invalid auxData";
    }
  }

  async getAPR(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    inputValue: bigint,
  ): Promise<number[]> {
    // Not taking into account how the deposited funds will change the yield
    if (auxData === 0n) {
      // Minting
      // The approximate number of blocks per year that is assumed by the interest rate model
      const blocksPerYear = 2102400;
      const supplyRatePerBlock = await ICERC20__factory.connect(
        outputAssetA.erc20Address.toString(),
        this.ethersProvider,
      ).supplyRatePerBlock();
      return [supplyRatePerBlock.mul(blocksPerYear).toNumber() / 10 ** 16];
    } else if (auxData === 1n) {
      // Redeeming
      return [0];
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
    let cTokenAddress;
    let underlyingAsset;
    if (auxData === 0n) {
      // Minting
      cTokenAddress = outputAssetA.erc20Address;
      underlyingAsset = inputAssetA;
    } else if (auxData === 1n) {
      // Redeeming
      cTokenAddress = inputAssetA.erc20Address;
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
        amount: marketSize.toBigInt(),
      },
    ];
  }

  private async isSupportedAsset(asset: AztecAsset): Promise<boolean> {
    if (asset.assetType == AztecAssetType.ETH) return true;

    const assetAddress = EthAddress.fromString(await this.rollupProcessor.getSupportedAsset(asset.id));
    return assetAddress.equals(asset.erc20Address);
  }

  private async getAllMarkets(): Promise<EthAddress[]> {
    if (!this.allMarkets) {
      // Load markets from Comptroller if they were not loaded in this class instance before
      this.allMarkets = (await this.comptroller.getAllMarkets()).map(stringAddr => {
        return EthAddress.fromString(stringAddr);
      });
    }
    return this.allMarkets;
  }
}
