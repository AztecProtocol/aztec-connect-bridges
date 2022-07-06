import { EthAddress } from "@aztec/barretenberg/address";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { JsonRpcProvider } from "@ethersproject/providers";
import { IComptroller, IComptroller__factory } from "../../../typechain-types";
import { createWeb3Provider } from "../aztec/provider";
import { AuxDataConfig, AztecAsset, BridgeDataFieldGetters, SolidityType } from "../bridge-data";

export class CompoundBridgeData implements BridgeDataFieldGetters {
  allMarkets?: EthAddress[];

  private constructor(private comptrollerContract: IComptroller) {}

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

  getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    inputValue: bigint,
  ): Promise<bigint[]> {
    throw new Error("Method not implemented.");
  }

  // NOTE: getAuxData not implemented because the method will not be relevant if use generic ERC4626 vault with wrappers

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

  private async getAllMarkets(): Promise<EthAddress[]> {
    if (!this.allMarkets) {
      const allMarketsStrings = await this.comptrollerContract.getAllMarkets();
      this.allMarkets = allMarketsStrings.map(stringAddr => {
        return EthAddress.fromString(stringAddr);
      });
    }
    return this.allMarkets;
  }
}
