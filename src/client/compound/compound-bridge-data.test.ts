import { ethers } from "ethers";
import { AztecAsset, AztecAssetType } from "../bridge-data";
import { CompoundBridgeData } from "./compound-bridge-data";

describe("compound lending bridge data", () => {
  let compoundBridgeData: CompoundBridgeData;

  let ethAsset: AztecAsset;
  let cethAsset: AztecAsset;
  let emptyAsset: AztecAsset;

  beforeAll(() => {
    const provider = new ethers.providers.JsonRpcProvider(
      "https://mainnet.infura.io/v3/9928b52099854248b3a096be07a6b23c",
    );
    compoundBridgeData = CompoundBridgeData.create(provider);
    ethAsset = {
      id: 1n,
      assetType: AztecAssetType.ETH,
      erc20Address: "0x0",
    };
    cethAsset = {
      id: 3n,
      assetType: AztecAssetType.ERC20,
      erc20Address: "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5",
    };
    emptyAsset = {
      id: 0n,
      assetType: AztecAssetType.NOT_USED,
      erc20Address: "0x0",
    };
  });

  it("should correctly fetch auxData when minting", async () => {
    const auxDataRedeem = await compoundBridgeData.getAuxData(ethAsset, emptyAsset, cethAsset, emptyAsset);
    expect(auxDataRedeem[0]).toBe(0n);
  });

  it("should correctly fetch auxData when redeeming", async () => {
    const auxDataRedeem = await compoundBridgeData.getAuxData(cethAsset, emptyAsset, ethAsset, emptyAsset);
    expect(auxDataRedeem[0]).toBe(1n);
  });

  it("should correctly compute expected output when minting", async () => {
    const expectedOutput = (
      await compoundBridgeData.getExpectedOutput(ethAsset, emptyAsset, cethAsset, emptyAsset, 0n, 10n ** 18n)
    )[0];
    // TODO: mock response and make the test more specific
    expect(expectedOutput).toBeGreaterThan(0);
  });

  it("should correctly compute expected output when redeeming", async () => {
    const expectedOutput = (
      await compoundBridgeData.getExpectedOutput(cethAsset, emptyAsset, ethAsset, emptyAsset, 1n, 4983783707n)
    )[0];
    // TODO: mock response and make the test more specific
    expect(expectedOutput).toBeGreaterThan(0);
  });

  it("should correctly compute expected yield when minting", async () => {
    const expectedYield = (
      await compoundBridgeData.getExpectedYield(ethAsset, emptyAsset, cethAsset, emptyAsset, 0n, 0n)
    )[0];
    // TODO: mock response and make the test more specific
    expect(expectedYield).toBeGreaterThan(0);
  });

  it("should compute expected yield to be 0 when redeeming", async () => {
    const expectedYield = (
      await compoundBridgeData.getExpectedYield(cethAsset, emptyAsset, ethAsset, emptyAsset, 1n, 0n)
    )[0];
    expect(expectedYield).toBe(0);
  });

  it("should correctly compute market size", async () => {
    const marketSizeMint = (await compoundBridgeData.getMarketSize(ethAsset, emptyAsset, cethAsset, emptyAsset, 0n))[0];
    const marketSizeRedeem = (
      await compoundBridgeData.getMarketSize(cethAsset, emptyAsset, ethAsset, emptyAsset, 1n)
    )[0];
    // TODO: mock response and make the test more specific
    expect(marketSizeMint.amount).toBe(marketSizeRedeem.amount);
    expect(marketSizeMint.amount).toBeGreaterThan(0);
  });
});
