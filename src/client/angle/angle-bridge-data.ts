import "isomorphic-fetch";

import { EthAddress } from "@aztec/barretenberg/address";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { Web3Provider } from "@ethersproject/providers";
import { IStableMaster, IStableMaster__factory } from "../../../typechain-types";
import { createWeb3Provider } from "../aztec/provider";
import { AuxDataConfig, AztecAsset, AztecAssetType, BridgeDataFieldGetters, SolidityType } from "../bridge-data";
import { AssetValue } from "@aztec/barretenberg/asset";

export class AngleBridgeData implements BridgeDataFieldGetters {
  readonly scalingFactor: bigint = 10n ** 18n;

  readonly DAI = "0x6B175474E89094C44Da98b954EedeAC495271d0F".toLowerCase();
  readonly USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48".toLowerCase();
  readonly WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2".toLowerCase();
  readonly FRAX = "0x853d955aCEf822Db058eb8505911ED77F175b99e".toLowerCase();

  readonly sanDAI = "0x7B8E89b0cE7BAC2cfEC92A371Da899eA8CBdb450".toLowerCase();
  readonly sanUSDC = "0x9C215206Da4bf108aE5aEEf9dA7caD3352A36Dad".toLowerCase();
  readonly sanWETH = "0x30c955906735e48D73080fD20CB488518A6333C8".toLowerCase();
  readonly sanFRAX = "0xb3B209Bb213A5Da5B947C56f2C770b3E1015f1FE".toLowerCase();

  readonly poolManagerDAI = "0xc9daabC677F3d1301006e723bD21C60be57a5915".toLowerCase();
  readonly poolManagerUSDC = "0xe9f183FC656656f1F17af1F2b0dF79b8fF9ad8eD".toLowerCase();
  readonly poolManagerWETH = "0x3f66867b4b6eCeBA0dBb6776be15619F73BC30A2".toLowerCase();
  readonly poolManagerFRAX = "0x6b4eE7352406707003bC6f6b96595FD35925af48".toLowerCase();

  readonly poolManagers = {
    [this.DAI]: this.poolManagerDAI,
    [this.USDC]: this.poolManagerUSDC,
    [this.WETH]: this.poolManagerWETH,
    [this.FRAX]: this.poolManagerFRAX,
  };

  allMarkets?: EthAddress[];

  private constructor(private ethersProvider: Web3Provider, private angleStableMaster: IStableMaster) {}

  static create(provider: EthereumProvider) {
    const ethersProvider = createWeb3Provider(provider);

    return new AngleBridgeData(
      createWeb3Provider(provider),
      IStableMaster__factory.connect("0x5adDc89785D75C86aB939E9e15bfBBb7Fc086A87", ethersProvider),
    );
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
  ): Promise<number[]> {
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
      return [0];
    } else if (this.poolManagers[outputAssetAAddress]) {
      const poolManager = this.poolManagers[outputAssetAAddress];
      const { sanToken } = await this.angleStableMaster.collateralMap(poolManager);
      if (sanToken.toLowerCase() !== inputAssetAAddress) throw "invalid inputAssetA";
      return [1];
    }

    throw "invalid input/output asset";
  }

  async getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: number,
    inputValue: bigint,
  ): Promise<bigint[]> {
    // first check if assets are valid
    const _auxData = await this.getAuxData(inputAssetA, inputAssetB, outputAssetA, outputAssetB);
    if (auxData !== _auxData[0]) throw "invalid auxData";

    if (auxData === 0) {
      const poolManager = this.poolManagers[inputAssetA.erc20Address.toString().toLowerCase()];
      const { sanRate } = await this.angleStableMaster.collateralMap(poolManager);
      return [(inputValue * this.scalingFactor) / sanRate.toBigInt()];
    } else if (auxData === 1) {
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
    auxData: number,
  ): Promise<AssetValue[]> {
    let poolManager: string;
    let token: AztecAsset;
    if (auxData === 0) {
      poolManager = this.poolManagers[inputAssetA.erc20Address.toString().toLowerCase()];
      token = inputAssetA;
    } else if (auxData === 1) {
      poolManager = this.poolManagers[outputAssetA.erc20Address.toString().toLowerCase()];
      token = outputAssetA;
    } else {
      throw "Invalid auxData";
    }

    const { stocksUsers } = await this.angleStableMaster.collateralMap(poolManager);
    return [{ assetId: token.id, value: stocksUsers.toBigInt() }];
  }

  async getAPR(yieldAsset: AztecAsset): Promise<number> {
    const apr = (await (await fetch("https://api.angle.money/v1/apr")).json()) as Record<
      string,
      { details: any; value: number; address: string }
    >;

    const sanTokenToGauge = {
      [this.sanDAI]: "0x8E2c0CbDa6bA7B65dbcA333798A3949B07638026".toLowerCase(),
      [this.sanUSDC]: "0x51fE22abAF4a26631b2913E417c0560D547797a7".toLowerCase(),
      [this.sanWETH]: "0x30c955906735e48D73080fD20CB488518A6333C8".toLowerCase(),
      [this.sanFRAX]: "0xb40432243E4F317cE287398e72Ab8f0312fc2FE8".toLowerCase(),
    };

    for (const data of Object.values(apr)) {
      const gauge = sanTokenToGauge[yieldAsset.erc20Address.toString().toLowerCase()];
      if (gauge === undefined) continue;
      if (data.address?.toLowerCase() === gauge) return data.value;
    }
    return 0;
  }
}
