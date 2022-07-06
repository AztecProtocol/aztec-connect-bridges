import { ethers } from "ethers";
import { AztecAsset, AztecAssetType } from "../bridge-data";
import { CompoundBridgeData } from "./compound-bridge-data";

describe("compound lending bridge data", () => {
  let compoundBridgeData: CompoundBridgeData;

  let ethAsset: AztecAsset;
  let wethAsset: AztecAsset;
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
    wethAsset = {
      id: 2n,
      assetType: AztecAssetType.ERC20,
      erc20Address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2",
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
});
