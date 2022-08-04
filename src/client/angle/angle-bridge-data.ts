import { EthAddress } from "@aztec/barretenberg/address";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { Web3Provider } from "@ethersproject/providers";
import { IStableMaster, IStableMaster__factory } from "../../../typechain-types";
import { createWeb3Provider } from "../aztec/provider";
import {
  AssetValue,
  AuxDataConfig,
  AztecAsset,
  AztecAssetType,
  BridgeDataFieldGetters,
  SolidityType,
} from "../bridge-data";

export class AngleBridgeData implements BridgeDataFieldGetters {
  readonly scalingFactor: bigint = 10n ** 18n;
  readonly poolManagers = {
    ["0x6B175474E89094C44Da98b954EedeAC495271d0F".toLowerCase()]:
      "0xc9daabC677F3d1301006e723bD21C60be57a5915".toLowerCase(),
    ["0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48".toLowerCase()]:
      "0xe9f183FC656656f1F17af1F2b0dF79b8fF9ad8eD".toLowerCase(),
    ["0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2".toLowerCase()]:
      "0x3f66867b4b6eCeBA0dBb6776be15619F73BC30A2".toLowerCase(),
    ["0x853d955aCEf822Db058eb8505911ED77F175b99e".toLowerCase()]:
      "0x6b4eE7352406707003bC6f6b96595FD35925af48".toLowerCase(),
  };

  allMarkets?: EthAddress[];

  private constructor(private ethersProvider: Web3Provider, private angleStableMaster: IStableMaster) {}

  static create(provider: EthereumProvider, angleStableMasterAddress: EthAddress) {
    const ethersProvider = createWeb3Provider(provider);
    const stableMaster = IStableMaster__factory.connect(angleStableMasterAddress.toString(), ethersProvider);

    return new AngleBridgeData(createWeb3Provider(provider), stableMaster);
  }

  public auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: "AuxData defines whether a deposit (0) or a withdraw (1) is executed",
    },
  ];

  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<bigint[]> {
    const inputAssetAAddress = inputAssetA.erc20Address.toString().toLowerCase();
    const outputAssetAAddress = outputAssetA.erc20Address.toString().toLowerCase();

    if (inputAssetAAddress === outputAssetAAddress) throw "inputAssetA and outputAssetA cannot be equal";

    if (inputAssetA.assetType !== AztecAssetType.ERC20 || outputAssetA.assetType !== AztecAssetType.ERC20) {
      throw "inputAssetA and outputAssetA must be ERC20";
    }

    if (this.poolManagers[inputAssetAAddress]) {
      const poolManager = this.poolManagers[inputAssetAAddress];
      const { sanToken } = await this.angleStableMaster.collateralMap(poolManager);
      if (sanToken.toLowerCase() !== outputAssetAAddress) throw "invalid outputAssetA";
      return [0n];
    } else if (this.poolManagers[outputAssetAAddress]) {
      const poolManager = this.poolManagers[outputAssetAAddress];
      const { sanToken } = await this.angleStableMaster.collateralMap(poolManager);
      if (sanToken.toLowerCase() !== inputAssetAAddress) throw "invalid inputAssetA";
      return [1n];
    }

    throw "invalid input/output asset";
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
      const poolManager = this.poolManagers[inputAssetA.erc20Address.toString().toLowerCase()];
      const { sanRate } = await this.angleStableMaster.collateralMap(poolManager);
      return [(inputValue * this.scalingFactor) / sanRate.toBigInt()];
    } else if (auxData === 1n) {
      const poolManager = this.poolManagers[outputAssetA.erc20Address.toString().toLowerCase()];
      const { sanRate } = await this.angleStableMaster.collateralMap(poolManager);
      return [(inputValue * sanRate.toBigInt()) / this.scalingFactor];
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
    let poolManager: string;
    let token: AztecAsset;
    if (auxData === 0n) {
      poolManager = this.poolManagers[inputAssetA.erc20Address.toString().toLowerCase()];
      token = inputAssetA;
    } else if (auxData === 1n) {
      poolManager = this.poolManagers[outputAssetA.erc20Address.toString().toLowerCase()];
      token = outputAssetA;
    } else {
      throw "Invalid auxData";
    }

    const { stocksUsers } = await this.angleStableMaster.collateralMap(poolManager);
    return [{ assetId: token.id, amount: stocksUsers.toBigInt() }];
  }
}
