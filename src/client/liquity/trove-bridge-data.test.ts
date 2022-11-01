import { EthAddress } from "@aztec/barretenberg/address";
import { BigNumber } from "ethers";
import {
  IPriceFeed,
  IPriceFeed__factory,
  ITroveManager,
  ITroveManager__factory,
  TroveBridge,
  TroveBridge__factory,
} from "../../../typechain-types";
import { AztecAsset, AztecAssetType } from "../bridge-data";
import { TroveBridgeData } from "./trove-bridge-data";

jest.mock("../aztec/provider", () => ({
  createWeb3Provider: jest.fn(),
}));

type Mockify<T> = {
  [P in keyof T]: jest.Mock | any;
};

describe("Liquity trove bridge data", () => {
  let troveBridge: Mockify<TroveBridge>;
  let troveManager: Mockify<ITroveManager>;
  let priceFeed: Mockify<IPriceFeed>;

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
    const troveBridgeData = TroveBridgeData.create({} as any, tbAsset.erc20Address);

    const auxDataBorrow = await troveBridgeData.getAuxData(ethAsset, emptyAsset, tbAsset, lusdAsset);
    expect(auxDataBorrow[0]).toBe(troveBridgeData.MAX_FEE);
  });

  it("should correctly fetch auxData when not borrowing", async () => {
    const troveBridgeData = TroveBridgeData.create({} as any, tbAsset.erc20Address);

    const auxDataBorrow = await troveBridgeData.getAuxData(tbAsset, lusdAsset, ethAsset, lusdAsset);
    expect(auxDataBorrow[0]).toBe(0);
  });

  it("should correctly get expected output when borrowing", async () => {
    // Setup mocks
    troveBridge = {
      ...troveBridge,
      callStatic: {
        computeAmtToBorrow: jest.fn().mockResolvedValue(BigNumber.from("1000000000000000000000")), // 1000 LUSD
      },
      address: tbAsset.erc20Address.toString(),
    };
    TroveBridge__factory.connect = () => troveBridge as any;

    const troveBridgeData = TroveBridgeData.create({} as any, tbAsset.erc20Address);

    const outputBorrow = await troveBridgeData.getExpectedOutput(
      ethAsset,
      emptyAsset,
      tbAsset,
      lusdAsset,
      troveBridgeData.MAX_FEE,
      10n ** 18n,
    );
    expect(outputBorrow[0]).toBe(10n ** 21n);
  });

  it("should correctly get expected output when repaying", async () => {
    // Setup mocks
    troveBridge = {
      ...troveBridge,
      totalSupply: jest.fn().mockResolvedValue(BigNumber.from("1000000000000000000000")), // 1000 TB
    };
    TroveBridge__factory.connect = () => troveBridge as any;

    troveManager = {
      ...troveManager,
      getEntireDebtAndColl: jest.fn().mockResolvedValue({
        debt: BigNumber.from("1000000000000000000000"), // 1000 LUSD
        coll: BigNumber.from("1000000000000000000000"), // 1000 ETH
        pendingLUSDDebtReward: BigNumber.from("0"), // not used - can be 0
        pendingETHReward: BigNumber.from("0"), // not used - can be 0
      }),
    };

    ITroveManager__factory.connect = () => troveManager as any;

    const troveBridgeData = TroveBridgeData.create({} as any, tbAsset.erc20Address);

    const inputValue = 10n ** 18n;
    const output = await troveBridgeData.getExpectedOutput(tbAsset, lusdAsset, ethAsset, lusdAsset, 0, inputValue);
    const expectedCollateralWithdrawn = inputValue;
    const lusdReturned = 0n;
    expect(output[0]).toBe(expectedCollateralWithdrawn);
    expect(output[1]).toBe(lusdReturned);
  });

  it("should correctly get borrowing fee out of recovery mode", async () => {
    // Setup mocks
    troveManager = {
      ...troveManager,
      priceFeed: jest.fn().mockResolvedValue(EthAddress.random().toString()),
      checkRecoveryMode: jest.fn().mockResolvedValue(false),
      getBorrowingRateWithDecay: jest.fn().mockResolvedValue(BigNumber.from("5000000000576535")),
    };

    ITroveManager__factory.connect = () => troveManager as any;

    priceFeed = {
      ...priceFeed,
      callStatic: {
        fetchPrice: jest.fn().mockResolvedValue(BigNumber.from("1000")),
      },
    };
    IPriceFeed__factory.connect = () => priceFeed as any;

    const troveBridgeData = TroveBridgeData.create({} as any, tbAsset.erc20Address);

    const borrowAmount = 1000n * 10n ** 18n; // 1000 LUSD
    const borrowingFee = await troveBridgeData.getBorrowingFee(borrowAmount);
    expect(borrowingFee).toBe(5000000000576535000n);
  });

  it("borrowing fee in recovery mode should be 0", async () => {
    // Setup mocks
    troveManager = {
      ...troveManager,
      priceFeed: jest.fn().mockResolvedValue(EthAddress.random().toString()),
      checkRecoveryMode: jest.fn().mockResolvedValue(true),
      getBorrowingRateWithDecay: jest.fn().mockResolvedValue(BigNumber.from("5000000000576535")),
    };

    ITroveManager__factory.connect = () => troveManager as any;

    priceFeed = {
      ...priceFeed,
      callStatic: {
        fetchPrice: jest.fn().mockResolvedValue(BigNumber.from("1000")),
      },
    };
    IPriceFeed__factory.connect = () => priceFeed as any;

    const troveBridgeData = TroveBridgeData.create({} as any, tbAsset.erc20Address);

    const borrowAmount = 1000n * 10n ** 18n; // 1000 LUSD
    const borrowingFee = await troveBridgeData.getBorrowingFee(borrowAmount);
    expect(borrowingFee).toBe(0n);
  });

  it("should correctly get current CR", async () => {
    // Setup mocks
    troveManager = {
      ...troveManager,
      priceFeed: jest.fn().mockResolvedValue(EthAddress.random().toString()),
      getCurrentICR: jest.fn().mockResolvedValue(BigNumber.from("2500000000000000000")),
    };

    ITroveManager__factory.connect = () => troveManager as any;

    priceFeed = {
      ...priceFeed,
      callStatic: {
        fetchPrice: jest.fn().mockResolvedValue(BigNumber.from("1000")),
      },
    };
    IPriceFeed__factory.connect = () => priceFeed as any;

    const troveBridgeData = TroveBridgeData.create({} as any, tbAsset.erc20Address);

    const currentCR = await troveBridgeData.getCurrentCR();
    expect(currentCR).toBe(250n);
  });

  it("should correctly get user's debt and collateral", async () => {
    // Setup mocks
    troveBridge = {
      ...troveBridge,
      totalSupply: jest.fn().mockResolvedValue(BigNumber.from("1000000000000000000000")), // 1000 TB
    };
    TroveBridge__factory.connect = () => troveBridge as any;

    troveManager = {
      ...troveManager,
      getEntireDebtAndColl: jest.fn().mockResolvedValue({
        debt: BigNumber.from("1000000000000000000000"), // 1000 LUSD
        coll: BigNumber.from("1000000000000000000000"), // 1000 ETH
        pendingLUSDDebtReward: BigNumber.from("0"), // not used - can be 0
        pendingETHReward: BigNumber.from("0"), // not used - can be 0
      }),
    };

    ITroveManager__factory.connect = () => troveManager as any;

    const troveBridgeData = TroveBridgeData.create({} as any, tbAsset.erc20Address);

    const inputValue = 10n ** 18n; // 1 TB
    const output = await troveBridgeData.getUserDebtAndCollateral(inputValue);

    const expectedCollateral = 10n ** 18n; // 1 ETH
    const expectedDebt = 10n ** 18n; // 1 LUSD
    expect(output[0]).toBe(expectedCollateral);
    expect(output[1]).toBe(expectedDebt);
  });
});
