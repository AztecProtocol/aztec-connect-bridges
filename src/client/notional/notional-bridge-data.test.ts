import { AztecAsset, AztecAssetType } from "../bridge-data";
import { BigNumber } from "ethers";
import { EthAddress } from "@aztec/barretenberg/address";
import { NotionalBridgeData } from "./notional-bridge-data";
import { NotionalViews, NotionalViews__factory } from "../../../typechain-types";

jest.mock("../aztec/provider", () => ({
  createWeb3Provider: jest.fn(),
}));

type Mockify<T> = {
  [P in keyof T]: jest.Mock | any;
};

describe("notional bridge data", () => {
  let notionalBridgeData: NotionalBridgeData;
  let daiAsset: AztecAsset;
  let emptyAsset: AztecAsset;
  let fcashDaiAsset: AztecAsset;
  let cdaiAsset: AztecAsset;
  let notionalViewContract: Mockify<NotionalViews>;

  const createNotionalBridgeData = (notionalView: NotionalViews = notionalViewContract as any) => {
    NotionalViews__factory.connect = () => notionalView as any;
    return NotionalBridgeData.create({} as any, EthAddress.ZERO);
  };

  beforeAll(() => {
    daiAsset = {
      id: 1,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0x6B175474E89094C44Da98b954EedeAC495271d0F"),
    };
    fcashDaiAsset = {
      id: 2,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0xfcB060E09e452EEFf142949Bec214c187CDF25fA"),
    };
    cdaiAsset = {
      id: 3,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643"),
    };
    emptyAsset = {
      id: 0,
      assetType: AztecAssetType.NOT_USED,
      erc20Address: EthAddress.ZERO,
    };
  });

  it("test get expected output of DAI", async () => {
    const input = BigNumber.from(BigInt(1e6));
    const expectedOutput = BigInt(1e6);
    notionalViewContract = {
      ...notionalViewContract,
      getMaxCurrencyId: jest.fn().mockReturnValue(2),
      getCurrencyId: jest.fn().mockReturnValue(2),
      getfCashAmountGivenCashAmount: jest.fn().mockReturnValue(BigNumber.from(BigInt(1e6))),
      getCurrency: jest.fn().mockReturnValue([
        {
          tokenAddress: cdaiAsset.erc20Address.toString(),
          hasTransferFee: false,
          decimals: BigNumber.from(8),
        },
        {
          tokenAddress: daiAsset.erc20Address.toString(),
          hasTransferFee: false,
          decimals: BigNumber.from(6),
        },
      ]),
    };
    notionalBridgeData = await createNotionalBridgeData(notionalViewContract as any);
    const output = await notionalBridgeData.getExpectedOutput(
      daiAsset,
      emptyAsset,
      fcashDaiAsset,
      emptyAsset,
      (
        await notionalBridgeData.getAuxData(daiAsset, emptyAsset, fcashDaiAsset, emptyAsset)
      )[0],
      input.toBigInt(),
    );
    expect(expectedOutput == output[0]).toBeTruthy();
  });
});
