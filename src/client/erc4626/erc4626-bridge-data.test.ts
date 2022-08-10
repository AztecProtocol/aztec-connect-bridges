import { EthAddress } from "@aztec/barretenberg/address";
import { IComptroller, IERC20, IRollupProcessor } from "../../../typechain-types";
import { AztecAsset, AztecAssetType } from "../bridge-data";
import { ERC4626BridgeData } from "./erc4626-bridge-data";

jest.mock("../aztec/provider", () => ({
  createWeb3Provider: jest.fn(),
}));

type Mockify<T> = {
  [P in keyof T]: jest.Mock | any;
};

describe("ERC4626 bridge data", () => {
  let comptrollerContract: Mockify<IComptroller>;
  let rollupProcessorContract: Mockify<IRollupProcessor>;
  let erc20Contract: Mockify<IERC20>;

  let ethAsset: AztecAsset;
  let mplAsset: AztecAsset;
  let xmplAsset: AztecAsset;
  let emptyAsset: AztecAsset;

  beforeAll(() => {
    ethAsset = {
      id: 0n,
      assetType: AztecAssetType.ETH,
      erc20Address: EthAddress.ZERO,
    };
    mplAsset = {
      id: 10n, // Asset has not yet been registered on RollupProcessor so this id is random
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0x33349B282065b0284d756F0577FB39c158F935e6"),
    };
    xmplAsset = {
      id: 1n,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0x4937A209D4cDbD3ecD48857277cfd4dA4D82914c"),
    };
    emptyAsset = {
      id: 0n,
      assetType: AztecAssetType.NOT_USED,
      erc20Address: EthAddress.ZERO,
    };
  });

  it("should correctly fetch auxData when issuing shares", async () => {
    const erc4626BridgeData = ERC4626BridgeData.create();

    const auxDataIssue = await erc4626BridgeData.getAuxData(mplAsset, emptyAsset, xmplAsset, emptyAsset);
    expect(auxDataIssue[0]).toBe(0n);
  });

  it("should correctly fetch auxData when redeeming shares", async () => {
    const erc4626BridgeData = ERC4626BridgeData.create();

    const auxDataRedeem = await erc4626BridgeData.getAuxData(xmplAsset, emptyAsset, mplAsset, emptyAsset);
    expect(auxDataRedeem[0]).toBe(1n);
  });

  it("should correctly compute expected output when issuing shares", async () => {
    const erc4626BridgeData = ERC4626BridgeData.create();

    const expectedOutput = (
      await erc4626BridgeData.getExpectedOutput(mplAsset, emptyAsset, xmplAsset, emptyAsset, 0n, 10n ** 18n)
    )[0];
    expect(expectedOutput).toBeGreaterThan(0n);
  });

  it("should correctly compute expected output when issuing shares", async () => {
    const erc4626BridgeData = ERC4626BridgeData.create();

    const expectedOutput = (
      await erc4626BridgeData.getExpectedOutput(xmplAsset, emptyAsset, mplAsset, emptyAsset, 1n, 10n ** 18n)
    )[0];
    expect(expectedOutput).toBeGreaterThan(0n);
  });

  it("should correctly compute market size", async () => {
    const erc4626BridgeData = ERC4626BridgeData.create();

    const marketSizeMint = (await erc4626BridgeData.getMarketSize(mplAsset, emptyAsset, xmplAsset, emptyAsset, 0n))[0];
    const marketSizeRedeem = (
      await erc4626BridgeData.getMarketSize(xmplAsset, emptyAsset, mplAsset, emptyAsset, 1n)
    )[0];
    expect(marketSizeMint.amount).toBe(marketSizeRedeem.amount);
    expect(marketSizeMint.amount).toBeGreaterThan(0n);
  });
});
