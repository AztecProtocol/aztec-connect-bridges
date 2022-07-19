import { ChainProperties, ElementBridgeData } from "./element-bridge-data";
import { BigNumber } from "ethers";
import { randomBytes } from "crypto";
import {
  IRollupProcessor,
  ElementBridge,
  IVault,
  ElementBridge__factory,
  IRollupProcessor__factory,
  IVault__factory,
} from "../../../typechain-types";
// TODO: simply import BridgeCallData once the name is changed on defi-bridge-project branch
import { BridgeId as BridgeCallData } from "@aztec/barretenberg/bridge_id";
import { AztecAssetType } from "../bridge-data";
import { EthAddress } from "@aztec/barretenberg/address";

jest.mock("../aztec/provider", () => ({
  createWeb3Provider: jest.fn(),
}));

type Mockify<T> = {
  [P in keyof T]: jest.Mock;
};

const tranche1DeploymentBlockNumber = 45n;
const tranche2DeploymentBlockNumber = 87n;

interface DefiEvent {
  encodedBridgeCallData: bigint;
  nonce: number;
  totalInputValue: bigint;
  blockNumber: number;
}

interface Interaction {
  quantityPT: BigNumber;
  trancheAddress: string;
  expiry: BigNumber;
  finalised: boolean;
  failed: boolean;
}

const interactions: { [key: number]: Interaction } = {};

describe("element bridge data", () => {
  let elementBridge: Mockify<ElementBridge>;
  let balancerContract: Mockify<IVault>;
  const now = Math.floor(Date.now() / 1000);
  const expiration1 = BigInt(now + 86400 * 60);
  const expiration2 = BigInt(now + 86400 * 90);
  const startDate = BigInt(now - 86400 * 30);
  const bridgeCallData1 = new BridgeCallData(1, 4, 4, undefined, undefined, Number(expiration1));
  const bridgeCallData2 = new BridgeCallData(1, 5, 5, undefined, undefined, Number(expiration2));
  const outputValue = 10n * 10n ** 18n;
  const testAddress = EthAddress.random();

  const defiEvents = [
    {
      encodedBridgeCallData: bridgeCallData1.toBigInt(),
      nonce: 56,
      totalInputValue: 56n * 10n ** 16n,
      blockNumber: 59,
    } as DefiEvent,
    {
      encodedBridgeCallData: bridgeCallData1.toBigInt(),
      nonce: 158,
      totalInputValue: 158n * 10n ** 16n,
      blockNumber: 62,
    } as DefiEvent,
    {
      encodedBridgeCallData: bridgeCallData1.toBigInt(),
      nonce: 190,
      totalInputValue: 190n * 10n ** 16n,
      blockNumber: 76,
    } as DefiEvent,
    {
      encodedBridgeCallData: bridgeCallData2.toBigInt(),
      nonce: 194,
      totalInputValue: 194n * 10n ** 16n,
      blockNumber: 91,
    } as DefiEvent,
    {
      encodedBridgeCallData: bridgeCallData1.toBigInt(),
      nonce: 203,
      totalInputValue: 203n * 10n ** 16n,
      blockNumber: 103,
    } as DefiEvent,
    {
      encodedBridgeCallData: bridgeCallData2.toBigInt(),
      nonce: 216,
      totalInputValue: 216n * 10n ** 16n,
      blockNumber: 116,
    } as DefiEvent,
    {
      encodedBridgeCallData: bridgeCallData2.toBigInt(),
      nonce: 227,
      totalInputValue: 227n * 10n ** 16n,
      blockNumber: 125,
    } as DefiEvent,
    {
      encodedBridgeCallData: bridgeCallData1.toBigInt(),
      nonce: 242,
      totalInputValue: 242n * 10n ** 16n,
      blockNumber: 134,
    } as DefiEvent,
    {
      encodedBridgeCallData: bridgeCallData1.toBigInt(),
      nonce: 289,
      totalInputValue: 289n * 10n ** 16n,
      blockNumber: 147,
    } as DefiEvent,
  ];

  const getDefiEvents = (nonce: number, from: number, to: number) => {
    return defiEvents.filter(x => x.nonce == nonce && x.blockNumber >= from && x.blockNumber <= to);
  };

  const getDefiEvent = (nonce: number) => {
    return defiEvents.find(x => x.nonce == nonce);
  };

  const getTrancheDeploymentBlockNumber = (nonce: bigint) => {
    const defiEvent = defiEvents.find(x => x.nonce == Number(nonce));
    if (defiEvent?.encodedBridgeCallData ?? 1n == 1n) {
      return tranche1DeploymentBlockNumber;
    }
    return tranche2DeploymentBlockNumber;
  };

  elementBridge = {
    interactions: jest.fn().mockImplementation(async (nonce: bigint) => {
      return interactions[Number(nonce)];
    }),
    getTrancheDeploymentBlockNumber: jest.fn().mockImplementation(async (nonce: bigint) => {
      const promise = Promise.resolve(getTrancheDeploymentBlockNumber(nonce));
      return promise;
    }),
    provider: {
      getBlockNumber: jest.fn().mockResolvedValue(200),
      getBlock: jest.fn().mockResolvedValue({ timestamp: +now.toString(), number: 200 }),
    },
  } as any;

  const rollupContract: Mockify<IRollupProcessor> = {
    queryFilter: jest.fn().mockImplementation((filter: any, from: number, to: number) => {
      const nonce = filter.interactionNonce;
      const [defiEvent] = getDefiEvents(nonce, from, to);
      if (defiEvent === undefined) {
        return [];
      }
      const bridgeCallData = BridgeCallData.fromBigInt(defiEvent.encodedBridgeCallData);
      return [
        {
          getBlock: jest.fn().mockResolvedValue({ timestamp: +startDate.toString(), number: defiEvent.blockNumber }),
          args: [
            BigNumber.from(bridgeCallData.toBigInt()),
            BigNumber.from(defiEvent.nonce),
            BigNumber.from(defiEvent.totalInputValue),
          ],
        },
      ];
    }),
    filters: {
      AsyncDefiBridgeProcessed: jest.fn().mockImplementation((bridgeCallData: any, interactionNonce: number) => {
        return {
          bridgeCallData,
          interactionNonce,
        };
      }),
    } as any,
  } as any;

  const createElementBridgeData = (
    element: ElementBridge = elementBridge as any,
    balancer: IVault = balancerContract as any,
    rollup: IRollupProcessor = rollupContract as any,
    chainProperties: ChainProperties = { eventBatchSize: 10 },
  ) => {
    ElementBridge__factory.connect = () => element as any;
    IVault__factory.connect = () => balancer as any;
    IRollupProcessor__factory.connect = () => rollup as any;
    return ElementBridgeData.create({} as any, EthAddress.ZERO, EthAddress.ZERO, EthAddress.ZERO, chainProperties); // can pass in dummy values here as the above factories do all of the work
  };

  it("should return the correct amount of interest", async () => {
    const elementBridgeData = createElementBridgeData();
    interactions[56] = {
      quantityPT: BigNumber.from(outputValue),
      expiry: BigNumber.from(expiration1),
      trancheAddress: "",
      finalised: false,
      failed: false,
    } as Interaction;
    const totalInput = defiEvents.find(x => x.nonce === 56)!.totalInputValue;
    const userShareDivisor = 2n;
    const defiEvent = getDefiEvent(56)!;
    const [daiValue] = await elementBridgeData.getInteractionPresentValue(56n, totalInput / userShareDivisor);
    const delta = outputValue - defiEvent.totalInputValue;
    const timeElapsed = BigInt(now) - startDate;
    const fullTime = expiration1 - startDate;
    const out = defiEvent.totalInputValue + (delta * timeElapsed) / fullTime;

    expect(daiValue.amount).toStrictEqual(out / userShareDivisor);
    expect(Number(daiValue.assetId)).toStrictEqual(bridgeCallData1.inputAssetIdA);
  });

  it("should return the correct amount of interest for multiple interactions", async () => {
    const elementBridgeData = createElementBridgeData();
    const testInteraction = async (nonce: number) => {
      const defiEvent = getDefiEvent(nonce)!;
      const bridgeCallData = BridgeCallData.fromBigInt(defiEvent.encodedBridgeCallData);
      interactions[nonce] = {
        quantityPT: BigNumber.from(10n * 10n ** 18n),
        expiry: BigNumber.from(bridgeCallData.auxData),
        trancheAddress: "",
        finalised: false,
        failed: false,
      } as Interaction;
      const totalInput = defiEvents.find(x => x.nonce === nonce)!.totalInputValue;
      const userShareDivisor = 2n;

      const [daiValue] = await elementBridgeData.getInteractionPresentValue(
        BigInt(nonce),
        totalInput / userShareDivisor,
      );
      const delta = interactions[nonce].quantityPT.toBigInt() - defiEvent.totalInputValue;
      const timeElapsed = BigInt(now) - startDate;
      const fullTime = BigInt(bridgeCallData.auxData) - startDate;
      const out = defiEvent.totalInputValue + (delta * timeElapsed) / fullTime;
      expect(daiValue.amount).toStrictEqual(out / userShareDivisor);
      expect(Number(daiValue.assetId)).toStrictEqual(bridgeCallData.inputAssetIdA);
    };
    await testInteraction(56);
    await testInteraction(190);
    await testInteraction(242);
    await testInteraction(216);
    await testInteraction(194);
    await testInteraction(203);
    await testInteraction(216);
    await testInteraction(190);
  });

  it("requesting the present value of an unknown interaction should return empty values", async () => {
    const elementBridgeData = createElementBridgeData();
    const values = await elementBridgeData.getInteractionPresentValue(57n, 0n);
    expect(values).toStrictEqual([]);
  });

  it("should return the correct expiration of the tranche", async () => {
    const endDate = Math.floor(Date.now() / 1000) + 86400 * 60;
    elementBridge = {
      interactions: jest.fn().mockImplementation(async () => {
        return {
          quantityPT: BigNumber.from(1),
          trancheAddress: "",
          expiry: BigNumber.from(endDate),
          finalised: false,
          failed: false,
        };
      }),
      provider: {
        getBlockNumber: jest.fn().mockResolvedValue(200),
        getBlock: jest.fn().mockResolvedValue({ timestamp: +now.toString(), number: 200 }),
      },
    } as any;

    const elementBridgeData = createElementBridgeData(elementBridge as any);
    const expiration = await elementBridgeData.getExpiration(1n);

    expect(expiration).toBe(BigInt(endDate));
  });

  it("should return the correct yield of the tranche", async () => {
    const now = Math.floor(Date.now() / 1000);
    const expiry = BigInt(now + 86400 * 30);
    const trancheAddress = "0x90ca5cef5b29342b229fb8ae2db5d8f4f894d652";
    const poolId = "0x90ca5cef5b29342b229fb8ae2db5d8f4f894d6520002000000000000000000b5";
    const interest = BigInt(1e16);
    const inputValue = BigInt(10e18),
      elementBridge = {
        hashAssetAndExpiry: jest.fn().mockResolvedValue("0xa"),
        pools: jest.fn().mockResolvedValue([trancheAddress, "", poolId]),
        provider: {
          getBlockNumber: jest.fn().mockResolvedValue(200),
          getBlock: jest.fn().mockResolvedValue({ timestamp: +now.toString(), number: 200 }),
        },
      };

    balancerContract = {
      ...balancerContract,
      queryBatchSwap: jest.fn().mockImplementation((...args) => {
        return Promise.resolve([BigNumber.from(inputValue), BigNumber.from(-BigInt(inputValue + interest))]);
      }),
    };

    const elementBridgeData = createElementBridgeData(
      elementBridge as any,
      balancerContract as any,
      rollupContract as any,
    );
    const output = await elementBridgeData.getAPR(
      {
        assetType: AztecAssetType.ERC20,
        erc20Address: testAddress,
        id: 1n,
      },
      {
        assetType: AztecAssetType.NOT_USED,
        erc20Address: EthAddress.ZERO,
        id: 0n,
      },
      {
        assetType: AztecAssetType.ERC20,
        erc20Address: testAddress,
        id: 1n,
      },
      {
        assetType: AztecAssetType.NOT_USED,
        erc20Address: EthAddress.ZERO,
        id: 0n,
      },
      expiry,
      BigInt(inputValue),
    );
    const YEAR = 60 * 60 * 24 * 365;
    const timeToExpiration = expiry - BigInt(now);
    const scaledOut = (BigInt(interest) * elementBridgeData.scalingFactor) / timeToExpiration;
    const yearlyOut = (scaledOut * BigInt(YEAR)) / elementBridgeData.scalingFactor;
    const scaledPercentage = (yearlyOut * elementBridgeData.scalingFactor) / inputValue;
    const percentage2sf = scaledPercentage / (elementBridgeData.scalingFactor / 10000n);
    const percent = Number(percentage2sf) / 100;

    expect(output[0]).toBe(percent);
  });

  it("should return the correct market size for a given tranche", async () => {
    const expiry = BigInt(Date.now() + 86400 * 30);
    const tokenAddress = EthAddress.random().toString();
    const poolId = "0x90ca5cef5b29342b229fb8ae2db5d8f4f894d6520002000000000000000000b5";
    const tokenBalance = 10e18,
      elementBridge = {
        hashAssetAndExpiry: jest.fn().mockResolvedValue("0xa"),
        pools: jest.fn().mockResolvedValue([tokenAddress, "", poolId]),
        provider: {
          getBlockNumber: jest.fn().mockResolvedValue(200),
          getBlock: jest.fn().mockResolvedValue({ timestamp: +now.toString(), number: 200 }),
        },
      };

    balancerContract = {
      ...balancerContract,
      getPoolTokens: jest.fn().mockResolvedValue([[tokenAddress], [BigNumber.from(BigInt(tokenBalance))]]),
    };

    const elementBridgeData = createElementBridgeData(
      elementBridge as any,
      balancerContract as any,
      rollupContract as any,
    );
    const marketSize = await elementBridgeData.getMarketSize(
      {
        assetType: AztecAssetType.ERC20,
        erc20Address: EthAddress.random(),
        id: 1n,
      },
      {
        assetType: AztecAssetType.NOT_USED,
        erc20Address: EthAddress.ZERO,
        id: 0n,
      },
      {
        assetType: AztecAssetType.ERC20,
        erc20Address: testAddress,
        id: 1n,
      },
      {
        assetType: AztecAssetType.NOT_USED,
        erc20Address: EthAddress.ZERO,
        id: 0n,
      },
      expiry,
    );
    expect(marketSize[0].assetId).toBe(BigInt(tokenAddress));
    expect(marketSize[0].amount).toBe(BigInt(tokenBalance));
    expect(marketSize.length).toBe(1);
  });
});
