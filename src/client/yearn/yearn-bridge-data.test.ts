import { YearnBridgeData } from "./yearn-bridge-data";
import {
  IYearnRegistry,
  IYearnRegistry__factory,
  IYearnVault__factory,
  IRollupProcessor,
  IRollupProcessor__factory,
  IYearnVault,
} from "../../../typechain-types";
import { AztecAsset, AztecAssetType } from "../bridge-data";
import { EthAddress } from "@aztec/barretenberg/address";
import { BigNumber } from "ethers";

jest.mock("../aztec/provider", () => ({
  createWeb3Provider: jest.fn(),
}));

type Mockify<T> = {
  [P in keyof T]: jest.Mock | any;
};

describe("Testing Yearn auxData", () => {
  let registryContract: Mockify<IYearnRegistry>;
  let rollupProcessorContract: Mockify<IRollupProcessor>;
  let ethAsset: AztecAsset;
  let wethAsset: AztecAsset;
  let yvEthAsset: AztecAsset;
  let daiAsset: AztecAsset;
  let yvDaiAsset: AztecAsset;
  let yvUSDCAsset: AztecAsset;
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
    yvDaiAsset = {
      id: 2n,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0xdA816459F1AB5631232FE5e97a05BBBb94970c95"),
    };
    yvEthAsset = {
      id: 3n,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0xa258c4606ca8206d8aa700ce2143d7db854d168c"),
    };
    wethAsset = {
      id: 4n,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"),
    };
    yvUSDCAsset = {
      id: 5n,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0xa354F35829Ae975e850e23e9615b11Da1B3dC4DE"),
    };
    emptyAsset = {
      id: 100n,
      assetType: AztecAssetType.NOT_USED,
      erc20Address: EthAddress.ZERO,
    };
  });

  it("should correctly fetch auxData for deposit", async () => {
    // Setup mocks
    const vaults = [yvDaiAsset.erc20Address.toString(), yvEthAsset.erc20Address.toString()];
    const underlying = [daiAsset.erc20Address.toString(), wethAsset.erc20Address.toString()];
    registryContract = {
      ...registryContract,
      numTokens: jest.fn(() => underlying.length),
      tokens: jest.fn((index: number) => underlying[index]),
      latestVault: jest.fn((tokenAddress: string) => {
        const indexOfToken = underlying.indexOf(tokenAddress);
        if (indexOfToken === -1) {
          throw new Error("Token not found");
        }
        return vaults[indexOfToken];
      }),
    };
    IYearnRegistry__factory.connect = () => registryContract as any;

    rollupProcessorContract = {
      ...rollupProcessorContract,
      getSupportedAsset: jest.fn((id: bigint) => {
        if (id === 1n) {
          return daiAsset.erc20Address.toString();
        } else if (id === 2n) {
          return yvDaiAsset.erc20Address.toString();
        } else if (id === 3n) {
          return yvEthAsset.erc20Address.toString();
        } else if (id === 4n) {
          return wethAsset.erc20Address.toString();
        }
      }),
    };
    IRollupProcessor__factory.connect = () => rollupProcessorContract as any;

    const yearnBridgeData = YearnBridgeData.create({} as any);
    const auxDataDepositERC20 = await yearnBridgeData.getAuxData(daiAsset, emptyAsset, yvDaiAsset, emptyAsset);
    expect(auxDataDepositERC20[0]).toBe(0n);
    const auxDataDepositETH = await yearnBridgeData.getAuxData(ethAsset, emptyAsset, yvEthAsset, emptyAsset);
    expect(auxDataDepositETH[0]).toBe(0n);
  });

  it("should correctly fetch auxData for withdrawal", async () => {
    // Setup mocks
    const vaults = [yvDaiAsset.erc20Address.toString(), yvEthAsset.erc20Address.toString()];
    const underlying = [daiAsset.erc20Address.toString(), wethAsset.erc20Address.toString()];
    registryContract = {
      ...registryContract,
      numTokens: jest.fn(() => underlying.length),
      tokens: jest.fn((index: number) => underlying[index]),
      latestVault: jest.fn((tokenAddress: string) => {
        const indexOfToken = underlying.indexOf(tokenAddress);
        if (indexOfToken === -1) {
          throw new Error("Token not found");
        }
        return vaults[indexOfToken];
      }),
    };
    IYearnRegistry__factory.connect = () => registryContract as any;

    rollupProcessorContract = {
      ...rollupProcessorContract,
      getSupportedAsset: jest.fn((id: bigint) => {
        if (id === 1n) {
          return daiAsset.erc20Address.toString();
        } else if (id === 2n) {
          return yvDaiAsset.erc20Address.toString();
        } else if (id === 3n) {
          return yvEthAsset.erc20Address.toString();
        } else if (id === 4n) {
          return wethAsset.erc20Address.toString();
        }
      }),
    };
    IRollupProcessor__factory.connect = () => rollupProcessorContract as any;

    const yearnBridgeData = YearnBridgeData.create({} as any);
    const auxDataDepositERC20 = await yearnBridgeData.getAuxData(yvDaiAsset, emptyAsset, daiAsset, emptyAsset);
    expect(auxDataDepositERC20[0]).toBe(1n);
    const auxDataDepositETH = await yearnBridgeData.getAuxData(yvEthAsset, emptyAsset, ethAsset, emptyAsset);
    expect(auxDataDepositETH[0]).toBe(1n);
  });

  it("should throw when getting auxData for unsupported inputAssetA", async () => {
    // Setup mocks
    const vaults = [yvDaiAsset.erc20Address.toString(), yvEthAsset.erc20Address.toString()];
    const underlying = [daiAsset.erc20Address.toString(), wethAsset.erc20Address.toString()];
    registryContract = {
      ...registryContract,
      numTokens: jest.fn(() => underlying.length),
      tokens: jest.fn((index: number) => underlying[index]),
      latestVault: jest.fn((tokenAddress: string) => {
        const indexOfToken = underlying.indexOf(tokenAddress);
        if (indexOfToken === -1) {
          throw new Error("Token not found");
        }
        return vaults[indexOfToken];
      }),
    };
    IYearnRegistry__factory.connect = () => registryContract as any;

    rollupProcessorContract = {
      ...rollupProcessorContract,
      getSupportedAsset: jest.fn().mockResolvedValue(EthAddress.random().toString()),
    };
    IRollupProcessor__factory.connect = () => rollupProcessorContract as any;

    const yearnBridgeData = YearnBridgeData.create({} as any);

    expect.assertions(1);
    await expect(yearnBridgeData.getAuxData(yvDaiAsset, emptyAsset, ethAsset, emptyAsset)).rejects.toEqual(
      "inputAssetA not supported",
    );
  });

  it("should throw when getting auxData for unsupported outputAssetA", async () => {
    // Setup mocks
    const vaults = [yvDaiAsset.erc20Address.toString(), yvEthAsset.erc20Address.toString()];
    const underlying = [daiAsset.erc20Address.toString(), wethAsset.erc20Address.toString()];
    registryContract = {
      ...registryContract,
      numTokens: jest.fn(() => underlying.length),
      tokens: jest.fn((index: number) => underlying[index]),
      latestVault: jest.fn((tokenAddress: string) => {
        const indexOfToken = underlying.indexOf(tokenAddress);
        if (indexOfToken === -1) {
          throw new Error("Token not found");
        }
        return vaults[indexOfToken];
      }),
    };
    IYearnRegistry__factory.connect = () => registryContract as any;

    rollupProcessorContract = {
      ...rollupProcessorContract,
      getSupportedAsset: jest.fn().mockResolvedValue(EthAddress.random().toString()),
    };
    IRollupProcessor__factory.connect = () => rollupProcessorContract as any;

    const yearnBridgeData = YearnBridgeData.create({} as any);

    expect.assertions(1);
    await expect(yearnBridgeData.getAuxData(ethAsset, emptyAsset, yvEthAsset, emptyAsset)).rejects.toEqual(
      "outputAssetA not supported",
    );
  });

  it("should throw when getting incompatible assets", async () => {
    // Setup mocks
    const vaults = [yvDaiAsset.erc20Address.toString(), yvEthAsset.erc20Address.toString()];
    const underlying = [daiAsset.erc20Address.toString(), wethAsset.erc20Address.toString()];
    registryContract = {
      ...registryContract,
      numTokens: jest.fn(() => underlying.length),
      tokens: jest.fn((index: number) => underlying[index]),
      latestVault: jest.fn((tokenAddress: string) => {
        const indexOfToken = underlying.indexOf(tokenAddress);
        if (indexOfToken === -1) {
          throw new Error("Token not found");
        }
        return vaults[indexOfToken];
      }),
    };
    IYearnRegistry__factory.connect = () => registryContract as any;

    rollupProcessorContract = {
      ...rollupProcessorContract,
      getSupportedAsset: jest.fn((id: bigint) => {
        if (id === 1n) {
          return daiAsset.erc20Address.toString();
        } else if (id === 2n) {
          return yvDaiAsset.erc20Address.toString();
        } else if (id === 3n) {
          return yvEthAsset.erc20Address.toString();
        } else if (id === 4n) {
          return wethAsset.erc20Address.toString();
        } else if (id === 5n) {
          return yvUSDCAsset.erc20Address.toString();
        }
      }),
    };
    IRollupProcessor__factory.connect = () => rollupProcessorContract as any;

    const yearnBridgeData = YearnBridgeData.create({} as any);

    expect.assertions(8);
    await expect(yearnBridgeData.getAuxData(ethAsset, emptyAsset, yvDaiAsset, emptyAsset)).rejects.toEqual(
      "Invalid input and/or output asset",
    );
    await expect(yearnBridgeData.getAuxData(daiAsset, emptyAsset, yvEthAsset, emptyAsset)).rejects.toEqual(
      "Invalid input and/or output asset",
    );
    await expect(yearnBridgeData.getAuxData(daiAsset, emptyAsset, ethAsset, emptyAsset)).rejects.toEqual(
      "Invalid input and/or output asset",
    );
    await expect(yearnBridgeData.getAuxData(daiAsset, emptyAsset, yvUSDCAsset, emptyAsset)).rejects.toEqual(
      "Invalid input and/or output asset",
    );

    await expect(yearnBridgeData.getAuxData(yvDaiAsset, emptyAsset, ethAsset, emptyAsset)).rejects.toEqual(
      "Invalid input and/or output asset",
    );
    await expect(yearnBridgeData.getAuxData(yvEthAsset, emptyAsset, daiAsset, emptyAsset)).rejects.toEqual(
      "Invalid input and/or output asset",
    );
    await expect(yearnBridgeData.getAuxData(ethAsset, emptyAsset, daiAsset, emptyAsset)).rejects.toEqual(
      "Invalid input and/or output asset",
    );
    await expect(yearnBridgeData.getAuxData(yvUSDCAsset, emptyAsset, daiAsset, emptyAsset)).rejects.toEqual(
      "Invalid input and/or output asset",
    );
  });
});

describe("Testing Yearn expectedOutput", () => {
  let vaultContract: Mockify<IYearnVault>;
  let ethAsset: AztecAsset;
  let yvEthAsset: AztecAsset;
  let daiAsset: AztecAsset;
  let yvDaiAsset: AztecAsset;
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
    yvDaiAsset = {
      id: 2n,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0xdA816459F1AB5631232FE5e97a05BBBb94970c95"),
    };
    yvEthAsset = {
      id: 3n,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0xa258c4606ca8206d8aa700ce2143d7db854d168c"),
    };
    emptyAsset = {
      id: 100n,
      assetType: AztecAssetType.NOT_USED,
      erc20Address: EthAddress.ZERO,
    };
  });

  it("should correctly get expectedOutput for deposit", async () => {
    // Setup mocks
    vaultContract = {
      ...vaultContract,
      pricePerShare: jest.fn(() => BigNumber.from("1010200000000000000")),
      decimals: jest.fn(() => BigNumber.from("18")),
    };
    IYearnVault__factory.connect = () => vaultContract as any;

    const yearnBridgeData = YearnBridgeData.create({} as any);

    const expectedOutputERC20 = await yearnBridgeData.getExpectedOutput(
      daiAsset,
      emptyAsset,
      yvDaiAsset,
      emptyAsset,
      0n,
      10n ** 18n,
    );
    expect(expectedOutputERC20[0]).toBe(989902989507028311n);
    expect(expectedOutputERC20[1]).toBe(0n);

    const expectedOutputETH = await yearnBridgeData.getExpectedOutput(
      ethAsset,
      emptyAsset,
      yvEthAsset,
      emptyAsset,
      0n,
      10n ** 18n,
    );
    expect(expectedOutputETH[0]).toBe(989902989507028311n);
    expect(expectedOutputETH[1]).toBe(0n);
  });

  it("should correctly get expectedOutput for withdrawal", async () => {
    // Setup mocks
    vaultContract = {
      ...vaultContract,
      pricePerShare: jest.fn(() => BigNumber.from("1110200000000000000")),
      decimals: jest.fn(() => BigNumber.from("18")),
    };
    IYearnVault__factory.connect = () => vaultContract as any;

    const yearnBridgeData = YearnBridgeData.create({} as any);

    const expectedOutputERC20 = await yearnBridgeData.getExpectedOutput(
      yvDaiAsset,
      emptyAsset,
      daiAsset,
      emptyAsset,
      1n,
      10n ** 18n,
    );
    expect(expectedOutputERC20[0]).toBe(1110200000000000000n);
    expect(expectedOutputERC20[1]).toBe(0n);

    const expectedOutputETH = await yearnBridgeData.getExpectedOutput(
      yvEthAsset,
      emptyAsset,
      ethAsset,
      emptyAsset,
      1n,
      10n ** 18n,
    );
    expect(expectedOutputETH[0]).toBe(1110200000000000000n);
    expect(expectedOutputETH[1]).toBe(0n);
  });

  it("should throw when getting incompatible auxData", async () => {
    // Setup mocks
    vaultContract = {
      ...vaultContract,
      pricePerShare: jest.fn(() => BigNumber.from("1110200000000000000")),
      decimals: jest.fn(() => BigNumber.from("18")),
    };
    IYearnVault__factory.connect = () => vaultContract as any;

    const yearnBridgeData = YearnBridgeData.create({} as any);

    expect.assertions(3);
    await expect(
      yearnBridgeData.getExpectedOutput(yvDaiAsset, emptyAsset, daiAsset, emptyAsset, 0n, 10n ** 18n),
    ).rejects.toEqual(new Error("Token not found"));
    await expect(
      yearnBridgeData.getExpectedOutput(daiAsset, emptyAsset, yvDaiAsset, emptyAsset, 1n, 10n ** 18n),
    ).rejects.toEqual(new Error("Token not found"));
    await expect(
      yearnBridgeData.getExpectedOutput(yvDaiAsset, emptyAsset, daiAsset, emptyAsset, 3n, 10n ** 18n),
    ).rejects.toEqual("Invalid auxData");
  });
});

describe("Testing Yearn getExpectedYield", () => {
  let ethAsset: AztecAsset;
  let wethAsset: AztecAsset;
  let daiAsset: AztecAsset;
  let yvDaiAsset: AztecAsset;
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
    yvDaiAsset = {
      id: 2n,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0xdA816459F1AB5631232FE5e97a05BBBb94970c95"),
    };
    wethAsset = {
      id: 4n,
      assetType: AztecAssetType.ERC20,
      erc20Address: EthAddress.fromString("0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2"),
    };
    emptyAsset = {
      id: 100n,
      assetType: AztecAssetType.NOT_USED,
      erc20Address: EthAddress.ZERO,
    };
  });

  it("should correctly get getExpectedYield", async () => {
    const yearnBridgeData = YearnBridgeData.create({} as any);
    const expectedOutputDAI = await yearnBridgeData.getExpectedYield?.(
      daiAsset,
      emptyAsset,
      emptyAsset,
      emptyAsset,
      0n,
      0n,
    );
    expect(expectedOutputDAI).not.toBeUndefined();
    expect((expectedOutputDAI as [number, number])[0]).toBeGreaterThan(0n);

    const expectedOutputWETH = await yearnBridgeData.getExpectedYield?.(
      wethAsset,
      emptyAsset,
      emptyAsset,
      emptyAsset,
      0n,
      0n,
    );
    expect(expectedOutputWETH).not.toBeUndefined();
    expect((expectedOutputWETH as [number, number])[0]).toBeGreaterThan(0n);

    const expectedOutputETH = await yearnBridgeData.getExpectedYield?.(
      ethAsset,
      emptyAsset,
      emptyAsset,
      emptyAsset,
      0n,
      0n,
    );
    expect(expectedOutputETH).not.toBeUndefined();
    expect((expectedOutputETH as [number, number])[0]).toBeGreaterThan(0n);
    expect((expectedOutputWETH as [number, number])[0]).toBe((expectedOutputETH as [number, number])[0]);

    await expect(
      yearnBridgeData.getExpectedOutput(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0n, 0n),
    ).rejects.toEqual(new Error("Token not found"));
    await expect(
      yearnBridgeData.getExpectedOutput(yvDaiAsset, emptyAsset, emptyAsset, emptyAsset, 0n, 0n),
    ).rejects.toEqual(new Error("Token not found"));
  });
});
