import { EthAddress } from "@aztec/barretenberg/address";
import { BigNumber } from "ethers";
import { IERC20Metadata, IERC20Metadata__factory, IERC4626, IERC4626__factory } from "../../../typechain-types";
import { AztecAsset, AztecAssetType } from "../bridge-data";
import { ERC4626BridgeData } from "./erc4626-bridge-data";

jest.mock("../aztec/provider", () => ({
  createWeb3Provider: jest.fn(),
}));

type Mockify<T> = {
  [P in keyof T]: jest.Mock | any;
};

describe("ERC4626 bridge data", () => {
  let erc4626Contract: Mockify<IERC4626>;
  let erc2MetadataContract: Mockify<IERC20Metadata>;

  let mplAsset: AztecAsset;
  let xmplAsset: AztecAsset;
  let emptyAsset: AztecAsset;

  beforeAll(() => {
    mplAsset = {
      id: 10, // Asset has not yet been registered on RollupProcessor so this id is random
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0x33349B282065b0284d756F0577FB39c158F935e6"),
    };
    xmplAsset = {
      id: 1,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0x4937A209D4cDbD3ecD48857277cfd4dA4D82914c"),
    };
    emptyAsset = {
      id: 0,
      assetType: AztecAssetType.NOT_USED,
      erc20Address: EthAddress.ZERO,
    };
  });

  it("should correctly fetch auxData when issuing shares", async () => {
    // Setup mocks
    erc4626Contract = {
      ...erc4626Contract,
      asset: jest.fn().mockResolvedValue(mplAsset.erc20Address.toString()),
    };
    IERC4626__factory.connect = () => erc4626Contract as any;

    const erc4626BridgeData = ERC4626BridgeData.create({} as any);

    // Test the code using mocked controller
    const auxDataIssue = await erc4626BridgeData.getAuxData(mplAsset, emptyAsset, xmplAsset, emptyAsset);
    expect(auxDataIssue[0]).toBe(0);
  });

  it("should correctly fetch auxData when redeeming shares", async () => {
    // Setup mocks
    erc4626Contract = {
      ...erc4626Contract,
      asset: jest.fn().mockResolvedValue(mplAsset.erc20Address.toString()),
    };
    IERC4626__factory.connect = () => erc4626Contract as any;

    const erc4626BridgeData = ERC4626BridgeData.create({} as any);

    // Test the code using mocked controller
    const auxDataRedeem = await erc4626BridgeData.getAuxData(xmplAsset, emptyAsset, mplAsset, emptyAsset);
    expect(auxDataRedeem[0]).toBe(1);
  });

  it("should correctly compute expected output when issuing shares", async () => {
    // Setup mocks
    erc4626Contract = {
      ...erc4626Contract,
      previewDeposit: jest.fn().mockResolvedValue(BigNumber.from("111111")),
    };
    IERC4626__factory.connect = () => erc4626Contract as any;

    const erc4626BridgeData = ERC4626BridgeData.create({} as any);

    // Test the code using mocked controller
    const expectedOutput = (
      await erc4626BridgeData.getExpectedOutput(mplAsset, emptyAsset, xmplAsset, emptyAsset, 0, 10n ** 18n)
    )[0];
    expect(expectedOutput).toBe(111111n);
  });

  it("should correctly compute expected output when redeeming shares", async () => {
    // Setup mocks
    erc4626Contract = {
      ...erc4626Contract,
      previewRedeem: jest.fn().mockResolvedValue(BigNumber.from("111111")),
    };
    IERC4626__factory.connect = () => erc4626Contract as any;

    const erc4626BridgeData = ERC4626BridgeData.create({} as any);

    // Test the code using mocked controller
    const expectedOutput = (
      await erc4626BridgeData.getExpectedOutput(xmplAsset, emptyAsset, mplAsset, emptyAsset, 1, 10n ** 18n)
    )[0];
    expect(expectedOutput).toBe(111111n);
  });

  it("should correctly get asset", async () => {
    // Setup mocks
    erc4626Contract = {
      ...erc4626Contract,
      asset: jest.fn().mockResolvedValue(mplAsset.erc20Address.toString()),
    };
    IERC4626__factory.connect = () => erc4626Contract as any;

    const erc4626BridgeData = ERC4626BridgeData.create({} as any);

    // Test the code using mocked controller
    const asset = await erc4626BridgeData.getAsset(xmplAsset.erc20Address);
    expect(asset.toString()).toBe(mplAsset.erc20Address.toString());
  });

  it("should correctly return underlying asset", async () => {
    // Setup mocks
    erc4626Contract = {
      ...erc4626Contract,
      asset: jest.fn().mockResolvedValue(mplAsset.erc20Address.toString()),
      previewRedeem: jest.fn(() => BigNumber.from("100")),
    };
    IERC4626__factory.connect = () => erc4626Contract as any;

    erc2MetadataContract = {
      ...erc2MetadataContract,
      name: jest.fn().mockResolvedValue("Maple Token"),
      symbol: jest.fn().mockResolvedValue("MPL"),
      decimals: jest.fn().mockResolvedValue(18),
    };
    IERC20Metadata__factory.connect = () => erc2MetadataContract as any;

    const erc4626BridgeData = ERC4626BridgeData.create({} as any);
    const underlyingAsset = await erc4626BridgeData.getUnderlyingAmount(xmplAsset, 10n ** 18n);

    expect(underlyingAsset.address.toString()).toBe(mplAsset.erc20Address.toString());
    expect(underlyingAsset.name).toBe("Maple Token");
    expect(underlyingAsset.symbol).toBe("MPL");
    expect(underlyingAsset.decimals).toBe(18);
    expect(underlyingAsset.amount).toBe(100n);
  });
});
