import { EthAddress } from "@aztec/barretenberg/address";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { Web3Provider } from "@ethersproject/providers";
import { createWeb3Provider } from "../aztec/provider";
import { AuxDataConfig, AztecAsset, AztecAssetType, BridgeDataFieldGetters, SolidityType } from "../bridge-data";

export class TroveBridgeData implements BridgeDataFieldGetters {
  public readonly LUSD = EthAddress.fromString("0x5f98805A4E8be255a32880FDeC7F6728C6568bA0");
  public readonly MAX_FEE = 2 * 10 ** 16; // 2 % borrowing fee

  protected constructor(protected ethersProvider: Web3Provider) {}

  static create(provider: EthereumProvider) {
    const ethersProvider = createWeb3Provider(provider);
    return new TroveBridgeData(ethersProvider);
  }

  auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: "AuxData is only used when borrowing and represent max borrowing fee",
    },
  ];

  /**
   * @dev Returns 2 percent borrowing fee when the input/output asset combination corresponds to borrowing. Return
   *      value is always 0 otherwise.
   * @dev I decided to return 2 % because it seems to be a reasonable value which should not cause revert
   *      in the future (Liquity's borrowing fee is currently 0.5 % and I don't expect it to rise above 2 %)
   */
  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<number[]> {
    if (
      inputAssetA.assetType === AztecAssetType.ETH &&
      inputAssetB.assetType === AztecAssetType.NOT_USED &&
      outputAssetB.erc20Address.equals(this.LUSD)
    ) {
      return [this.MAX_FEE];
    }
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
    if (auxData === 0) {
      // Issuing
      return [0n];
    } else if (auxData === 1) {
      // Redeeming
      return [0n];
    } else {
      throw "Invalid auxData";
    }
  }
}
