import {
  AssetValue,
  AuxDataConfig,
  AztecAsset,
  SolidityType,
  AztecAssetType,
  BridgeDataFieldGetters,
} from "../bridge-data";

import {
  IAaveLendingBridge,
  IAaveLendingBridge__factory,
  IERC20,
  IERC20__factory,
  ILendingPool,
  ILendingPool__factory,
} from "../../../typechain-types";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { createWeb3Provider } from "../aztec/provider";
import { EthAddress } from "@aztec/barretenberg/address";

export class AaveBridgeData implements BridgeDataFieldGetters {
  public scalingFactor: bigint = 1n * 10n ** 18n;

  private constructor(
    private lendingPoolContract: ILendingPool,
    private aaveLendingBridgeContract: IAaveLendingBridge,
  ) {}

  static create(provider: EthereumProvider, lendingPoolAddress: EthAddress, lendingBridgeAddress: EthAddress) {
    const ethersProvider = createWeb3Provider(provider);
    const poolContract = ILendingPool__factory.connect(lendingPoolAddress.toString(), ethersProvider);
    const lendingContract = IAaveLendingBridge__factory.connect(lendingBridgeAddress.toString(), ethersProvider);
    return new AaveBridgeData(poolContract, lendingContract);
  }

  // Unused
  public auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: "Not Used",
    },
  ];

  // Unused
  async getInteractionPresentValue(interactionNonce: bigint): Promise<AssetValue[]> {
    return [];
  }

  // Unused
  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<bigint[]> {
    return [0n];
  }

  async getUnderlyingAndEntering(
    inputAssetA: AztecAsset,
    outputAssetA: AztecAsset,
  ): Promise<{ underlyingAsset: EthAddress; entering: boolean }> {
    const WETH = EthAddress.fromString("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");

    let underlyingAsset: EthAddress;
    let entering: boolean;

    if (inputAssetA.assetType == AztecAssetType.ETH || outputAssetA.assetType == AztecAssetType.ETH) {
      if ((await this.aaveLendingBridgeContract.underlyingToZkAToken(WETH.toString())) == EthAddress.ZERO.toString()) {
        throw "ETH is not listed";
      }
    }

    if (inputAssetA.assetType == AztecAssetType.ETH) {
      underlyingAsset = WETH;
      entering = true;
    } else if (outputAssetA.assetType == AztecAssetType.ETH) {
      underlyingAsset = WETH;
      entering = false;
    } else {
      const candidateOut = await this.aaveLendingBridgeContract.underlyingToZkAToken(
        inputAssetA.erc20Address.toString(),
      );
      if (candidateOut != EthAddress.ZERO.toString()) {
        underlyingAsset = inputAssetA.erc20Address;
        entering = true;
      } else {
        const candidateIn = await this.aaveLendingBridgeContract.underlyingToZkAToken(
          outputAssetA.erc20Address.toString(),
        );
        if (candidateIn != EthAddress.ZERO.toString()) {
          underlyingAsset = outputAssetA.erc20Address;
          entering = false;
        } else {
          throw "Asset is not listed";
        }
      }
    }
    return { underlyingAsset, entering };
  }

  async getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    inputValue: bigint,
  ): Promise<bigint[]> {
    const { entering, underlyingAsset } = await this.getUnderlyingAndEntering(inputAssetA, outputAssetA);

    const normalizer: bigint = (
      await this.lendingPoolContract.getReserveNormalizedIncome(underlyingAsset.toString())
    ).toBigInt();
    const precision = 10n ** 27n;

    if (entering) {
      const expectedOut = (inputValue * precision) / normalizer;
      return [expectedOut];
    } else {
      const expectedOut = (inputValue * normalizer) / precision;
      return [expectedOut];
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
    const YEAR = 60n * 60n * 24n * 365n;

    const { entering, underlyingAsset } = await this.getUnderlyingAndEntering(inputAssetA, outputAssetA);

    if (!entering) {
      return [0];
    }

    // Not taking into account how the deposited funds will change the yield
    const reserveData = await this.lendingPoolContract.getReserveData(underlyingAsset.toString());
    const rate = reserveData.currentLiquidityRate.toBigInt();
    return [Number(rate / 10n ** 25n)];
  }

  async getMarketSize(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
  ): Promise<AssetValue[]> {
    const { underlyingAsset } = await this.getUnderlyingAndEntering(inputAssetA, outputAssetA);
    const reserveData = await this.lendingPoolContract.getReserveData(underlyingAsset.toString());
    const token = IERC20__factory.connect(reserveData.aTokenAddress, this.aaveLendingBridgeContract.provider);

    return [
      {
        assetId: inputAssetA.id,
        amount: (await token.totalSupply()).toBigInt(),
      },
    ];
  }
}
