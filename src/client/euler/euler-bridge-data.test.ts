import { EthAddress } from "@aztec/barretenberg/address";
import { BigNumber } from "ethers";
import { IERC4626, IERC4626__factory, ILidoOracle, ILidoOracle__factory } from "../../../typechain-types/index.js";
import { AztecAsset, AztecAssetType } from "../bridge-data.js";
import { EulerBridgeData } from "./euler-bridge-data.js";

jest.mock("../aztec/provider", () => ({
  createWeb3Provider: jest.fn(),
}));

type Mockify<T> = {
  [P in keyof T]: jest.Mock | any;
};

describe("Euler bridge data", () => {
  let erc4626Contract: Mockify<IERC4626>;
  let lidoOracleContract: Mockify<ILidoOracle>;

  let ethAsset: AztecAsset;
  let weDaiAsset: AztecAsset;
  let daiAsset: AztecAsset;
  let weWstethAsset: AztecAsset;
  let wstethAsset: AztecAsset;
  let emptyAsset: AztecAsset;

  beforeAll(() => {
    ethAsset = {
      id: 0,
      assetType: AztecAssetType.ETH,
      erc20Address: EthAddress.ZERO,
    };
    weDaiAsset = {
      id: 7,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0x4169Df1B7820702f566cc10938DA51F6F597d264"),
    };
    daiAsset = {
      id: 1,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0x6b175474e89094c44da98b954eedeac495271d0f"),
    };
    weWstethAsset = {
      id: 7,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0x60897720AA966452e8706e74296B018990aEc527"),
    };
    wstethAsset = {
      id: 1,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0"),
    };
    emptyAsset = {
      id: 0,
      assetType: AztecAssetType.NOT_USED,
      erc20Address: EthAddress.ZERO,
    };
  });

  it("should correctly fetch APR", async () => {
    erc4626Contract = {
      ...erc4626Contract,
      asset: jest.fn().mockResolvedValue(daiAsset.erc20Address.toString()),
    };
    IERC4626__factory.connect = () => erc4626Contract as any;

    const eulerBridgeData = EulerBridgeData.create({} as any);
    const apr = await eulerBridgeData.getAPR(weDaiAsset);
    expect(apr).toBeGreaterThan(0);
  });

  it("should correctly fetch APR for wstETH", async () => {
    const mockedLidoAPR = 4.32;

    erc4626Contract = {
      ...erc4626Contract,
      asset: jest.fn().mockResolvedValue(wstethAsset.erc20Address.toString()),
    };
    IERC4626__factory.connect = () => erc4626Contract as any;

    lidoOracleContract = {
      ...lidoOracleContract,
      getLastCompletedReportDelta: jest.fn().mockResolvedValue({
        timeElapsed: BigNumber.from(86400n),
        postTotalPooledEther: BigNumber.from(2777258873714679039007057n),
        preTotalPooledEther: BigNumber.from(2776930205843708039007057n),
      }),
    };
    ILidoOracle__factory.connect = () => lidoOracleContract as any;

    const eulerBridgeData = EulerBridgeData.createWithLido({} as any, {} as any);
    const combinedEulerLidoAPR = await eulerBridgeData.getAPR(weWstethAsset);
    expect(combinedEulerLidoAPR).toBeGreaterThan(mockedLidoAPR);
  });

  it("should correctly fetch market size", async () => {
    const eulerBridgeData = EulerBridgeData.create({} as any);
    const assetValue = (await eulerBridgeData.getMarketSize(daiAsset, emptyAsset, emptyAsset, emptyAsset, 0n))[0];
    expect(assetValue.assetId).toBe(daiAsset.id);
    expect(assetValue.value).toBeGreaterThan(0);
  });

  it("should correctly fetch market size for ETH", async () => {
    const eulerBridgeData = EulerBridgeData.create({} as any);
    const assetValue = (await eulerBridgeData.getMarketSize(ethAsset, emptyAsset, emptyAsset, emptyAsset, 0n))[0];
    expect(assetValue.assetId).toBe(ethAsset.id);
    expect(assetValue.value).toBeGreaterThan(0);
  });
});
