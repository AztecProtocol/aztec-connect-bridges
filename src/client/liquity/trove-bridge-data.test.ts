import { EthAddress } from "@aztec/barretenberg/address";
import { AztecAsset, AztecAssetType } from "../bridge-data";
import { TroveBridgeData } from "./trove-bridge-data";

jest.mock("../aztec/provider", () => ({
  createWeb3Provider: jest.fn(),
}));

type Mockify<T> = {
  [P in keyof T]: jest.Mock | any;
};

describe("ERC4626 bridge data", () => {
  let ethAsset: AztecAsset;
  let lusdAsset: AztecAsset;
  let tbAsset: AztecAsset;
  let emptyAsset: AztecAsset;

  beforeAll(() => {
    ethAsset = {
      id: 1,
      assetType: AztecAssetType.ETH,
      erc20Address: EthAddress.ZERO,
    };
    lusdAsset = {
      id: 10, // Asset has not yet been registered on RollupProcessor so this id is random
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0x5f98805A4E8be255a32880FDeC7F6728C6568bA0"),
    };
    tbAsset = {
      id: 11, // Asset has not yet been registered on RollupProcessor so this id is random
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.random(),
    };
    emptyAsset = {
      id: 0,
      assetType: AztecAssetType.NOT_USED,
      erc20Address: EthAddress.ZERO,
    };
  });

  it("should correctly fetch auxData when borrowing", async () => {
    const troveBridgeData = TroveBridgeData.create({} as any);

    // Test the code using mocked controller
    const auxDataBorrow = await troveBridgeData.getAuxData(ethAsset, emptyAsset, tbAsset, lusdAsset);
    expect(auxDataBorrow[0]).toBe(troveBridgeData.MAX_FEE);
  });

  it("should correctly fetch auxData when not borrowing", async () => {
    const troveBridgeData = TroveBridgeData.create({} as any);

    // Test the code using mocked controller
    const auxDataBorrow = await troveBridgeData.getAuxData(tbAsset, lusdAsset, ethAsset, lusdAsset);
    expect(auxDataBorrow[0]).toBe(0);
  });
});
