import { LidoBridgeData } from "./lido-bridge-data";
import {
  IWstETH,
  ICurvePool,
  ILidoOracle,
  IWstETH__factory,
  ICurvePool__factory,
  ILidoOracle__factory,
} from "../../../typechain-types";
import { AztecAsset, AztecAssetType } from "../bridge-data";
import { BigNumber } from "ethers";
import { EthAddress } from "@aztec/barretenberg/address";

jest.mock("../aztec/provider", () => ({
  createWeb3Provider: jest.fn(),
}));

type Mockify<T> = {
  [P in keyof T]: jest.Mock | any;
};

describe("lido bridge data", () => {
  let lidoBridgeData: LidoBridgeData;
  let wstethContract: Mockify<IWstETH>;
  let curvePoolContract: Mockify<ICurvePool>;
  let lidoOracleContract: Mockify<ILidoOracle>;

  let ethAsset: AztecAsset;
  let wstETHAsset: AztecAsset;
  let emptyAsset: AztecAsset;

  const createLidoBridgeData = (
    wsteth: IWstETH = wstethContract as any,
    curvePool: ICurvePool = curvePoolContract as any,
    lidoOracle: ILidoOracle = lidoOracleContract as any,
  ) => {
    IWstETH__factory.connect = () => wsteth as any;
    ICurvePool__factory.connect = () => curvePool as any;
    ILidoOracle__factory.connect = () => lidoOracle as any;
    return LidoBridgeData.create({} as any, EthAddress.ZERO, EthAddress.ZERO, EthAddress.ZERO); // can pass in dummy values here as the above factories do all of the work
  };

  beforeAll(() => {
    ethAsset = {
      id: 1n,
      assetType: AztecAssetType.ETH,
      erc20Address: EthAddress.ZERO,
    };
    wstETHAsset = {
      id: 2n,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0"),
    };
    emptyAsset = {
      id: 0n,
      assetType: AztecAssetType.NOT_USED,
      erc20Address: EthAddress.ZERO,
    };
  });

  it("should get wstETH when deposit small amount of ETH", async () => {
    const depositAmount = BigInt(10e18);
    const wstEthAmount = BigInt(9.5e18);
    const expectedOutput = wstEthAmount;

    wstethContract = {
      ...wstethContract,
      getWstETHByStETH: jest.fn().mockResolvedValue(BigNumber.from(wstEthAmount)),
    };

    lidoBridgeData = createLidoBridgeData(wstethContract as any, curvePoolContract as any, lidoOracleContract as any);

    const output = await lidoBridgeData.getExpectedOutput(
      ethAsset,
      emptyAsset,
      wstETHAsset,
      emptyAsset,
      0n,
      depositAmount,
    );
    expect(expectedOutput == output[0]).toBeTruthy();
  });
  it("should get wstETH when deposit a large amount of ETH", async () => {
    const depositAmount = BigInt(10000e18);
    const wstEthAmount = BigInt(9500e18);
    const expectedOutput = wstEthAmount;

    wstethContract = {
      ...wstethContract,
      getWstETHByStETH: jest.fn().mockResolvedValue(BigNumber.from(wstEthAmount)),
    };

    lidoBridgeData = createLidoBridgeData(wstethContract as any, curvePoolContract as any, lidoOracleContract as any);

    const output = await lidoBridgeData.getExpectedOutput(
      ethAsset,
      emptyAsset,
      wstETHAsset,
      emptyAsset,
      0n,
      depositAmount,
    );
    expect(expectedOutput == output[0]).toBeTruthy();
  });
  it("should exit to ETH when deposit WstETH", async () => {
    const depositAmount = BigInt(100e18);
    const stethOutputAmount = BigInt(110e18);
    const expectedOutput = BigInt(105e18);

    wstethContract = {
      ...wstethContract,
      getStETHByWstETH: jest.fn().mockResolvedValue(BigNumber.from(stethOutputAmount)),
    };

    curvePoolContract = {
      ...curvePoolContract,
      get_dy: jest.fn().mockResolvedValue(BigNumber.from(expectedOutput)),
    };

    lidoBridgeData = createLidoBridgeData(wstethContract as any, curvePoolContract as any, lidoOracleContract as any);

    const output = await lidoBridgeData.getExpectedOutput(
      wstETHAsset,
      emptyAsset,
      ethAsset,
      emptyAsset,
      0n,
      depositAmount,
    );

    expect(expectedOutput == output[0]).toBeTruthy();
  });

  it("should correctly return the expectedYearlyOutput", async () => {
    const depositAmount = BigInt(1 * 10e18);
    const expectedOutput = 4.32;

    wstethContract = {
      ...wstethContract,
      getStETHByWstETH: jest.fn().mockImplementation(async input => {
        // force WSTETH and STETH to have the same value
        return BigNumber.from((BigInt(input) * 100n) / 100n);
      }),
    };

    curvePoolContract = {
      ...curvePoolContract,
      get_dy: jest.fn().mockImplementation(async (x, y, input) => {
        // force ETH and STETH to have the same value
        return BigNumber.from((BigInt(input) * 100n) / 100n);
      }),
    };

    lidoOracleContract = {
      ...lidoOracleContract,
      getLastCompletedReportDelta: jest.fn().mockResolvedValue({
        timeElapsed: BigNumber.from(86400n),
        postTotalPooledEther: BigNumber.from(2777258873714679039007057n),
        preTotalPooledEther: BigNumber.from(2776930205843708039007057n),
      }),
    };

    lidoBridgeData = createLidoBridgeData(wstethContract as any, curvePoolContract as any, lidoOracleContract as any);

    const output = await lidoBridgeData.getAPR(wstETHAsset, emptyAsset, ethAsset, emptyAsset, 0n, depositAmount);
    expect(expectedOutput).toBe(output[0]);
  });
});
