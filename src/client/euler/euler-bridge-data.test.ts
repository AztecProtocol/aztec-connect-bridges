import { EthAddress } from "@aztec/barretenberg/address";
import { IERC4626, IERC4626__factory } from "../../../typechain-types";
import { AztecAsset, AztecAssetType } from "../bridge-data";
import { EulerBridgeData } from "./euler-bridge-data";

jest.mock("../aztec/provider", () => ({
  createWeb3Provider: jest.fn(),
}));

type Mockify<T> = {
  [P in keyof T]: jest.Mock | any;
};

describe("Euler bridge data", () => {
  let erc4626Contract: Mockify<IERC4626>;

  let ethAsset: AztecAsset;
  let weDaiAsset: AztecAsset;
  let daiAsset: AztecAsset;
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

  it("should correctly fetch market size", async () => {
    const eulerBridgeData = EulerBridgeData.create({} as any);
    const assetValue = (await eulerBridgeData.getMarketSize(daiAsset, emptyAsset, emptyAsset, emptyAsset, 0))[0];
    expect(assetValue.assetId).toBe(daiAsset.id);
    expect(assetValue.value).toBeGreaterThan(0);
  });
});
