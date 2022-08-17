import { EthAddress } from "@aztec/barretenberg/address";
import { BigNumber } from "ethers";
import {
  ICERC20,
  ICERC20__factory,
  IComptroller,
  IComptroller__factory,
  IERC20,
  IERC20__factory,
  IRollupProcessor,
  IRollupProcessor__factory,
} from "../../../typechain-types";
import { AztecAsset, AztecAssetType } from "../bridge-data";
import { CompoundBridgeData } from "./compound-bridge-data";

jest.mock("../aztec/provider", () => ({
  createWeb3Provider: jest.fn(),
}));

type Mockify<T> = {
  [P in keyof T]: jest.Mock | any;
};

describe("compound lending bridge data", () => {
  let comptrollerContract: Mockify<IComptroller>;
  let rollupProcessorContract: Mockify<IRollupProcessor>;
  let cerc20Contract: Mockify<ICERC20>;
  let erc20Contract: Mockify<IERC20>;

  let ethAsset: AztecAsset;
  let cethAsset: AztecAsset;
  let daiAsset: AztecAsset;
  let cdaiAsset: AztecAsset;
  let emptyAsset: AztecAsset;

  beforeAll(() => {
    ethAsset = {
      id: 0,
      assetType: AztecAssetType.ETH,
      erc20Address: EthAddress.ZERO,
    };
    cethAsset = {
      id: 10, // Asset has not yet been registered on RollupProcessor so this id is random
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5"),
    };
    daiAsset = {
      id: 1,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0x6B175474E89094C44Da98b954EedeAC495271d0F"),
    };
    cdaiAsset = {
      id: 11, // Asset has not yet been registered on RollupProcessor so this id is random
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643"),
    };
    emptyAsset = {
      id: 0,
      assetType: AztecAssetType.NOT_USED,
      erc20Address: EthAddress.ZERO,
    };
  });

  it("should correctly fetch auxData when minting", async () => {
    // Setup mocks
    const allMarkets = [cethAsset.erc20Address.toString()];
    comptrollerContract = {
      ...comptrollerContract,
      getAllMarkets: jest.fn().mockResolvedValue(allMarkets),
    };
    IComptroller__factory.connect = () => comptrollerContract as any;

    rollupProcessorContract = {
      ...rollupProcessorContract,
      getSupportedAsset: jest.fn().mockResolvedValue(cethAsset.erc20Address.toString()),
    };
    IRollupProcessor__factory.connect = () => rollupProcessorContract as any;

    const compoundBridgeData = CompoundBridgeData.create({} as any);

    // Test the code using mocked controller
    const auxDataRedeem = await compoundBridgeData.getAuxData(ethAsset, emptyAsset, cethAsset, emptyAsset);
    expect(auxDataRedeem[0]).toBe(0);
  });

  it("should correctly fetch auxData when redeeming", async () => {
    // Setup mocks
    const allMarkets = [cethAsset.erc20Address.toString()];
    comptrollerContract = {
      ...comptrollerContract,
      getAllMarkets: jest.fn().mockResolvedValue(allMarkets),
    };
    IComptroller__factory.connect = () => comptrollerContract as any;

    rollupProcessorContract = {
      ...rollupProcessorContract,
      getSupportedAsset: jest.fn().mockResolvedValue(cethAsset.erc20Address.toString()),
    };
    IRollupProcessor__factory.connect = () => rollupProcessorContract as any;

    const compoundBridgeData = CompoundBridgeData.create({} as any);

    // Test the code using mocked controller
    const auxDataRedeem = await compoundBridgeData.getAuxData(cethAsset, emptyAsset, ethAsset, emptyAsset);
    expect(auxDataRedeem[0]).toBe(1);
  });

  it("should throw when getting auxData for unsupported inputAssetA", async () => {
    // Setup mocks
    const allMarkets = [cethAsset.erc20Address.toString()];
    comptrollerContract = {
      ...comptrollerContract,
      getAllMarkets: jest.fn().mockResolvedValue(allMarkets),
    };
    IComptroller__factory.connect = () => comptrollerContract as any;

    rollupProcessorContract = {
      ...rollupProcessorContract,
      getSupportedAsset: jest.fn().mockResolvedValue(EthAddress.random().toString()),
    };
    IRollupProcessor__factory.connect = () => rollupProcessorContract as any;

    const compoundBridgeData = CompoundBridgeData.create({} as any);

    expect.assertions(1);
    await expect(compoundBridgeData.getAuxData(cethAsset, emptyAsset, ethAsset, emptyAsset)).rejects.toEqual(
      "inputAssetA not supported",
    );
  });

  it("should throw when getting auxData for unsupported outputAssetA", async () => {
    // Setup mocks
    const allMarkets = [cethAsset.erc20Address.toString()];
    comptrollerContract = {
      ...comptrollerContract,
      getAllMarkets: jest.fn().mockResolvedValue(allMarkets),
    };
    IComptroller__factory.connect = () => comptrollerContract as any;

    rollupProcessorContract = {
      ...rollupProcessorContract,
      getSupportedAsset: jest.fn().mockResolvedValue(EthAddress.random().toString()),
    };
    IRollupProcessor__factory.connect = () => rollupProcessorContract as any;

    const compoundBridgeData = CompoundBridgeData.create({} as any);

    expect.assertions(1);
    await expect(compoundBridgeData.getAuxData(ethAsset, emptyAsset, cethAsset, emptyAsset)).rejects.toEqual(
      "outputAssetA not supported",
    );
  });

  it("should correctly compute expected output when minting", async () => {
    // Setup mocks
    cerc20Contract = {
      ...cerc20Contract,
      exchangeRateStored: jest.fn().mockResolvedValue(BigNumber.from("200651191829205352408835886")),
    };
    ICERC20__factory.connect = () => cerc20Contract as any;
    const compoundBridgeData = CompoundBridgeData.create({} as any);

    // Test the code using mocked controller
    const expectedOutput = (
      await compoundBridgeData.getExpectedOutput(ethAsset, emptyAsset, cethAsset, emptyAsset, 0, 10n ** 18n)
    )[0];
    expect(expectedOutput).toBe(4983773038n);
  });

  it("should correctly compute expected output when redeeming", async () => {
    // Setup mocks
    cerc20Contract = {
      ...cerc20Contract,
      exchangeRateStored: jest.fn().mockResolvedValue(BigNumber.from("200651191829205352408835886")),
    };
    ICERC20__factory.connect = () => cerc20Contract as any;
    const compoundBridgeData = CompoundBridgeData.create({} as any);

    // Test the code using mocked controller
    const expectedOutput = (
      await compoundBridgeData.getExpectedOutput(cethAsset, emptyAsset, ethAsset, emptyAsset, 1, 4983783707n)
    )[0];
    expect(expectedOutput).toBe(1000002140628525162n);
  });

  it("should correctly compute expected APR", async () => {
    // Setup mocks
    cerc20Contract = {
      ...cerc20Contract,
      supplyRatePerBlock: jest.fn().mockResolvedValue(BigNumber.from("338149955")),
    };
    ICERC20__factory.connect = () => cerc20Contract as any;
    const compoundBridgeData = CompoundBridgeData.create({} as any);

    // Test the code using mocked controller
    const APR = await compoundBridgeData.getAPR(cethAsset);
    expect(APR).toBe(0.0710926465392);
  });

  it("should correctly compute market size", async () => {
    // Setup mocks
    erc20Contract = {
      ...erc20Contract,
      balanceOf: jest.fn().mockResolvedValue(BigNumber.from("368442895892448315882277748")),
    };
    IERC20__factory.connect = () => erc20Contract as any;
    const compoundBridgeData = CompoundBridgeData.create({} as any);

    // Test the code using mocked controller
    const marketSizeMint = (await compoundBridgeData.getMarketSize(daiAsset, emptyAsset, cdaiAsset, emptyAsset, 0))[0];
    const marketSizeRedeem = (
      await compoundBridgeData.getMarketSize(cdaiAsset, emptyAsset, daiAsset, emptyAsset, 1)
    )[0];
    expect(marketSizeMint.value).toBe(marketSizeRedeem.value);
    expect(marketSizeMint.value).toBe(368442895892448315882277748n);
  });
});
