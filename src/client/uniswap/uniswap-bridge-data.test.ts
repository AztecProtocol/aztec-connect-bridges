import { EthAddress } from "@aztec/barretenberg/address";
import { BigNumber } from "ethers";
import { UniswapBridge, UniswapBridge__factory } from "../../../typechain-types";
import { AztecAsset, AztecAssetType } from "../bridge-data";
import { UniswapBridgeData } from "./uniswap-bridge-data";

jest.mock("../aztec/provider", () => ({
  createWeb3Provider: jest.fn(),
}));

type Mockify<T> = {
  [P in keyof T]: jest.Mock | any;
};

describe("compound lending bridge data", () => {
  let uniswapBridge: Mockify<UniswapBridge>;

  let ethAsset: AztecAsset;
  let daiAsset: AztecAsset;
  let emptyAsset: AztecAsset;

  beforeAll(() => {
    ethAsset = {
      id: 0n,
      assetType: AztecAssetType.ETH,
      erc20Address: EthAddress.ZERO,
    };
    daiAsset = {
      id: 1n,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0x6B175474E89094C44Da98b954EedeAC495271d0F"),
    };
    emptyAsset = {
      id: 0n,
      assetType: AztecAssetType.NOT_USED,
      erc20Address: EthAddress.ZERO,
    };
  });

  it("should correctly compute expected output when minting", async () => {
    // Setup mocks
    uniswapBridge = {
      ...uniswapBridge,
      callStatic: { quote: jest.fn().mockResolvedValue(BigNumber.from(10n ** 18n)) },
    };
    UniswapBridge__factory.connect = () => uniswapBridge as any;
    const uniswapBridgeData = UniswapBridgeData.create({} as any, EthAddress.random());

    // Test the code using mocked controller
    const expectedOutput = (
      await uniswapBridgeData.getExpectedOutput(daiAsset, emptyAsset, ethAsset, emptyAsset, 0n, 10n ** 18n)
    )[0];
    expect(expectedOutput).toBe(10n ** 18n);
  });
});
