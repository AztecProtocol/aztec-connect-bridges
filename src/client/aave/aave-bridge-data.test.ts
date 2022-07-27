import { AaveBridgeData } from "./aave-bridge-data";
import {
  ILendingPool,
  IAaveLendingBridge,
  ILendingPool__factory,
  IAaveLendingBridge__factory,
} from "../../../typechain-types";
import { AztecAsset, AztecAssetType } from "../bridge-data";
import { BigNumber, BigNumberish } from "ethers";
import { EthAddress } from "@aztec/barretenberg/address";

jest.mock("../aztec/provider", () => ({
  createWeb3Provider: jest.fn(),
}));

type Mockify<T> = {
  [P in keyof T]: jest.Mock | any;
};

describe("aave lending bridge data", () => {
  let aaveBridgeData: AaveBridgeData;

  let lendingPoolContract: Mockify<ILendingPool>;
  let aaveLendingBridgeContract: Mockify<IAaveLendingBridge>;

  let ethAsset: AztecAsset;
  let wethAsset: AztecAsset;
  let emptyAsset: AztecAsset;

  const createAaveBridgeData = (
    lendingPool: ILendingPool = lendingPoolContract as any,
    aaveBridge: IAaveLendingBridge = aaveLendingBridgeContract as any,
  ) => {
    ILendingPool__factory.connect = () => lendingPool as any;
    IAaveLendingBridge__factory.connect = () => aaveBridge as any;

    return AaveBridgeData.create({} as any, EthAddress.ZERO, EthAddress.ZERO);
  };

  type ReserveConfigurationMapStruct = { data: BigNumberish };
  type ReserveDataStruct = {
    configuration: ReserveConfigurationMapStruct;
    liquidityIndex: BigNumberish;
    variableBorrowIndex: BigNumberish;
    currentLiquidityRate: BigNumberish;
    currentVariableBorrowRate: BigNumberish;
    currentStableBorrowRate: BigNumberish;
    lastUpdateTimestamp: BigNumberish;
    aTokenAddress: string;
    stableDebtTokenAddress: string;
    variableDebtTokenAddress: string;
    interestRateStrategyAddress: string;
    id: BigNumberish;
  };

  beforeAll(() => {
    ethAsset = {
      id: 1n,
      assetType: AztecAssetType.ETH,
      erc20Address: EthAddress.ZERO,
    };
    wethAsset = {
      id: 2n,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"),
    };
    emptyAsset = {
      id: 0n,
      assetType: AztecAssetType.NOT_USED,
      erc20Address: EthAddress.ZERO,
    };
  });

  it("should get zkaWeth when deposit eth", async () => {
    const depositAmount = 10n ** 18n;
    const normalizer = 110n * 10n ** 25n;
    const precision = 10n ** 27n;
    const expectedOutput = (depositAmount * precision) / normalizer;

    const zkAsset = {
      id: 3n,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.random(),
    };

    aaveLendingBridgeContract = {
      ...aaveLendingBridgeContract,
      underlyingToZkAToken: jest.fn().mockResolvedValue(zkAsset.erc20Address),
    };

    lendingPoolContract = {
      ...lendingPoolContract,
      getReserveNormalizedIncome: jest.fn().mockResolvedValue(BigNumber.from(normalizer)),
    };

    aaveBridgeData = createAaveBridgeData(lendingPoolContract as any, aaveLendingBridgeContract as any);

    const output = await aaveBridgeData.getExpectedOutput(ethAsset, emptyAsset, zkAsset, emptyAsset, 0n, depositAmount);

    expect(expectedOutput).toBe(output[0]);
    expect(output[0]).toBeLessThan(depositAmount);
  });

  it("should get eth when withdrawing zkweth", async () => {
    const depositAmount = 10n ** 18n;
    const normalizer = 110n * 10n ** 25n;
    const precision = 10n ** 27n;
    const expectedOutput = (depositAmount * normalizer) / precision;

    const zkAsset = {
      id: 3n,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.random(),
    };

    aaveLendingBridgeContract = {
      ...aaveLendingBridgeContract,
      underlyingToZkAToken: jest.fn().mockResolvedValue(zkAsset.erc20Address.toString()),
    };

    lendingPoolContract = {
      ...lendingPoolContract,
      getReserveNormalizedIncome: jest.fn().mockResolvedValue(BigNumber.from(normalizer)),
    };

    aaveBridgeData = createAaveBridgeData(lendingPoolContract as any, aaveLendingBridgeContract as any);

    const output = await aaveBridgeData.getExpectedOutput(zkAsset, emptyAsset, ethAsset, emptyAsset, 0n, depositAmount);

    expect(expectedOutput).toBe(output[0]);
    expect(output[0]).toBeGreaterThan(depositAmount);
  });

  it("should return the expected yield when entering", async () => {
    const depositAmount = 10n ** 18n;
    const zkAsset = {
      id: 3n,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.random(),
    };

    const rate = 3n * 10n ** 25n;

    const reserveData: ReserveDataStruct = {
      configuration: { data: 0 },
      liquidityIndex: 0,
      variableBorrowIndex: 0,
      currentLiquidityRate: BigNumber.from(rate),
      currentVariableBorrowRate: 0,
      currentStableBorrowRate: 0,
      lastUpdateTimestamp: 0,
      aTokenAddress: EthAddress.random().toString(),
      stableDebtTokenAddress: EthAddress.random().toString(),
      variableDebtTokenAddress: EthAddress.random().toString(),
      interestRateStrategyAddress: EthAddress.random().toString(),
      id: 0,
    };

    aaveLendingBridgeContract = {
      ...aaveLendingBridgeContract,
      underlyingToZkAToken: jest.fn().mockResolvedValue(zkAsset.erc20Address.toString()),
    };

    lendingPoolContract = {
      ...lendingPoolContract,
      getReserveData: jest.fn().mockResolvedValue(reserveData),
    };

    aaveBridgeData = createAaveBridgeData(lendingPoolContract as any, aaveLendingBridgeContract as any);

    const output = await aaveBridgeData.getAPR(ethAsset, emptyAsset, zkAsset, emptyAsset, 0n, depositAmount);

    expect(output[0]).toBe(3);
  });

  it("should return the expected yield when exiting", async () => {
    const depositAmount = 10n ** 18n;
    const zkAsset = {
      id: 3n,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.random(),
    };

    const rate = 3n * 10n ** 25n;
    const reserveData: ReserveDataStruct = {
      configuration: { data: 0 },
      liquidityIndex: 0,
      variableBorrowIndex: 0,
      currentLiquidityRate: BigNumber.from(rate),
      currentVariableBorrowRate: 0,
      currentStableBorrowRate: 0,
      lastUpdateTimestamp: 0,
      aTokenAddress: EthAddress.random().toString(),
      stableDebtTokenAddress: EthAddress.random().toString(),
      variableDebtTokenAddress: EthAddress.random().toString(),
      interestRateStrategyAddress: EthAddress.random().toString(),
      id: 0,
    };

    aaveLendingBridgeContract = {
      ...aaveLendingBridgeContract,
      underlyingToZkAToken: jest.fn().mockResolvedValue(zkAsset.erc20Address.toString()),
    };

    lendingPoolContract = {
      ...lendingPoolContract,
      getReserveData: jest.fn().mockResolvedValue(reserveData),
    };

    aaveBridgeData = createAaveBridgeData(lendingPoolContract as any, aaveLendingBridgeContract as any);

    const output = await aaveBridgeData.getAPR(zkAsset, emptyAsset, ethAsset, emptyAsset, 0n, depositAmount);

    expect(output[0]).toBe(0);
  });

  it.skip("should return the market size", async () => {
    const zkAsset = {
      id: 3n,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.random(),
    };

    aaveLendingBridgeContract = {
      ...aaveLendingBridgeContract,
      underlyingToZkAToken: jest.fn().mockResolvedValue(zkAsset.erc20Address).toString(),
    };

    aaveBridgeData = createAaveBridgeData(lendingPoolContract as any, aaveLendingBridgeContract as any);
  });
});
