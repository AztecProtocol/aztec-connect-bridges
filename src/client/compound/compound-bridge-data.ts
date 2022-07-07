import { EthAddress } from "@aztec/barretenberg/address";
import { JsonRpcProvider, Provider } from "@ethersproject/providers";
import { BigNumber } from "ethers";
import { ICERC20__factory, IComptroller, IComptroller__factory, IERC20__factory } from "../../../typechain-types";
import {
  AssetValue,
  AuxDataConfig,
  AztecAsset,
  AztecAssetType,
  BridgeDataFieldGetters,
  SolidityType,
} from "../bridge-data";

export class CompoundBridgeData implements BridgeDataFieldGetters {
  expScale = 10n ** 18n;
  ethersProvider: Provider;
  allMarkets?: EthAddress[];

  private constructor(private comptrollerContract: IComptroller) {
    this.ethersProvider = this.comptrollerContract.provider;
  }

  // TODO: use generic provider instead of ether's one
  // static create(provider: EthereumProvider) {
  static create(provider: JsonRpcProvider) {
    // const ethersProvider = createWeb3Provider(provider);
    const ethersProvider = provider;
    const comptrollerContract = IComptroller__factory.connect(
      "0x3d9819210A31b4961b30EF54bE2aeD79B9c9Cd3B",
      ethersProvider,
    );

    return new CompoundBridgeData(comptrollerContract);
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

    if (allMarkets.some(addr => addr.toString() == inputAssetA.erc20Address)) {
      return [1n];
    } else if (allMarkets.some(addr => addr.toString() == outputAssetA.erc20Address)) {
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
      const cToken = ICERC20__factory.connect(outputAssetA.erc20Address, this.ethersProvider);
      const exchangeRateStored = await cToken.exchangeRateStored();
      return [BigNumber.from(inputValue).mul(this.expScale).div(exchangeRateStored).toBigInt()];
    } else if (auxData === 1n) {
      // Redeeming
      const cToken = ICERC20__factory.connect(inputAssetA.erc20Address, this.ethersProvider);
      const exchangeRateStored = await cToken.exchangeRateStored();
      return [BigNumber.from(inputValue).mul(exchangeRateStored).div(this.expScale).toBigInt()];
    } else {
      throw "Invalid auxData";
    }
  }

  async getExpectedYield(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    precision: bigint,
  ): Promise<number[]> {
    // Not taking into account how the deposited funds will change the yield
    if (auxData === 0n) {
      // Minting
      // The approximate number of blocks per year that is assumed by the interest rate model
      const blocksPerYear = 2102400;
      const supplyRatePerBlock = await ICERC20__factory.connect(
        outputAssetA.erc20Address,
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
      marketSize = await this.ethersProvider.getBalance(cTokenAddress);
    } else {
      marketSize = await IERC20__factory.connect(outputAssetA.erc20Address, this.ethersProvider).balanceOf(
        cTokenAddress,
      );
    }
    return [
      {
        assetId: underlyingAsset.id,
        amount: marketSize.toBigInt(),
      },
    ];
  }

  private async getAllMarkets(): Promise<EthAddress[]> {
    if (!this.allMarkets) {
      this.allMarkets = (await this.comptrollerContract.getAllMarkets()).map(stringAddr => {
        return EthAddress.fromString(stringAddr);
      });
    }
    return this.allMarkets;
  }
}
