import { ElementBridgeData } from './element-bridge-data';
import { BigNumber, Signer } from 'ethers';
import { randomBytes } from 'crypto';
import { RollupProcessor, ElementBridge, IVault } from '../../../typechain-types';
import { BridgeId, BitConfig } from '../aztec/bridge_id';
import { AztecAssetType } from '../bridge-data';
import { AddressZero } from '@ethersproject/constants';

type Mockify<T> = {
  [P in keyof T]: jest.Mock;
};

const randomAddress = () => `0x${randomBytes(20).toString('hex')}`;

describe('element bridge data', () => {
  let rollupContract: Mockify<RollupProcessor>;
  let elementBridge: Mockify<ElementBridge>;
  let balancerContract: Mockify<IVault>;

  it('should return the correct amount of interest', async () => {
    const inputValue = 1n * 10n ** 18n;
    const outputValue = 10n * 10n ** 18n;
    const now = Math.floor(Date.now() / 1000);
    const expiration = BigInt(now + 86400 * 60);
    const startDate = BigInt(now - 86400 * 30);

    elementBridge = {
      interactions: jest.fn().mockImplementation(() => {
        return {
          quantityPT: BigNumber.from(outputValue),
          trancheAddress: '',
          expiry: BigNumber.from(expiration),
          finalised: false,
          failed: false,
        };
      }),
      getTrancheDeploymentBlockNumber: jest.fn().mockResolvedValue((nonce: bigint) => BigNumber.from(100000n)),
    } as any;
    const bridgeId = new BridgeId(67, 123, 456, 7890, 78, new BitConfig(false, true, false, true, false, false), 78);

    rollupContract = {
      ...rollupContract,
      queryFilter: jest.fn().mockResolvedValue([
        {
          getBlock: jest.fn().mockResolvedValue({ timestamp: +startDate.toString() }),
          args: [bridgeId, undefined, BigNumber.from(inputValue)],
        },
      ]),
      filters: {
        DefiBridgeProcessed: jest.fn(),
      } as any,
    };
    const elementBridgeData = new ElementBridgeData(
      elementBridge as any,
      balancerContract as any,
      rollupContract as any,
    );
    const [daiValue] = await elementBridgeData.getInteractionPresentValue(inputValue);
    const delta = outputValue - inputValue;
    const scalingFactor = elementBridgeData.scalingFactor;
    const ratio = ((BigInt(now) - startDate) * scalingFactor) / (expiration - startDate);
    const out = inputValue + (delta * ratio) / scalingFactor;

    expect(daiValue.amount).toBe(out);
    expect(daiValue.assetId).toBe(123n);
  });

  it('should return the correct expiration of the tranche', async () => {
    const endDate = Math.floor(Date.now() / 1000) + 86400 * 60;

    elementBridge = {
      interactions: jest.fn().mockImplementation(() => {
        return {
          quantityPT: BigNumber.from(1),
          trancheAddress: '',
          expiry: BigNumber.from(endDate),
          finalised: false,
          failed: false,
        };
      }),
    } as any;

    const elementBridgeData = new ElementBridgeData(
      elementBridge as any,
      balancerContract as any,
      rollupContract as any,
    );
    const expiration = await elementBridgeData.getExpiration(1n);

    expect(expiration).toBe(BigInt(endDate));
  });

  it('should return the correct yearly output of the tranche', async () => {
    const now = Math.floor(Date.now() / 1000);
    const expiry = BigInt(now + 86400 * 30);
    const trancheAddress = '0x90ca5cef5b29342b229fb8ae2db5d8f4f894d652';
    const poolId = '0x90ca5cef5b29342b229fb8ae2db5d8f4f894d6520002000000000000000000b5';
    const interest = 100000n;
    const inputValue = 10e18,
      elementBridge = {
        hashAssetAndExpiry: jest.fn().mockResolvedValue('0xa'),
        pools: jest.fn().mockResolvedValue([trancheAddress, '', poolId]),
      };

    balancerContract = {
      ...balancerContract,
      queryBatchSwap: jest.fn().mockImplementation((...args) => {
        const amount = args[1][0].amount;

        return Promise.resolve([BigNumber.from(BigInt(amount)), BigNumber.from(-BigInt(BigInt(amount) + interest))]);
      }),
    };

    const elementBridgeData = new ElementBridgeData(
      elementBridge as any,
      balancerContract as any,
      rollupContract as any,
    );
    const output = await elementBridgeData.getExpectedYearlyOuput(
      {
        assetType: AztecAssetType.ERC20,
        erc20Address: 'test',
        id: 1n,
      },
      {
        assetType: AztecAssetType.NOT_USED,
        erc20Address: AddressZero,
        id: 0n,
      },
      {
        assetType: AztecAssetType.ERC20,
        erc20Address: 'test',
        id: 1n,
      },
      {
        assetType: AztecAssetType.NOT_USED,
        erc20Address: AddressZero,
        id: 0n,
      },
      expiry,
      BigInt(inputValue),
    );
    const YEAR = 60 * 60 * 24 * 365;
    const timeToExpiration = expiry - BigInt(now);
    const scaledOut = (BigInt(interest) * elementBridgeData.scalingFactor) / timeToExpiration;
    const yearlyOut = (scaledOut * BigInt(YEAR)) / elementBridgeData.scalingFactor;

    expect(output[0]).toBe(yearlyOut + BigInt(inputValue));
  });

  it('should return the correct market size for a given tranche', async () => {
    const expiry = BigInt(Date.now() + 86400 * 30);
    const tokenAddress = randomAddress();
    const poolId = '0x90ca5cef5b29342b229fb8ae2db5d8f4f894d6520002000000000000000000b5';
    const tokenBalance = 10e18,
      elementBridge = {
        hashAssetAndExpiry: jest.fn().mockResolvedValue('0xa'),
        pools: jest.fn().mockResolvedValue([tokenAddress, '', poolId]),
      };

    balancerContract = {
      ...balancerContract,
      getPoolTokens: jest.fn().mockResolvedValue([[tokenAddress], [BigNumber.from(BigInt(tokenBalance))]]),
    };

    const elementBridgeData = new ElementBridgeData(
      elementBridge as any,
      balancerContract as any,
      rollupContract as any,
    );
    const marketSize = await elementBridgeData.getMarketSize(
      {
        assetType: AztecAssetType.ERC20,
        erc20Address: 'test',
        id: 1n,
      },
      {
        assetType: AztecAssetType.NOT_USED,
        erc20Address: AddressZero,
        id: 0n,
      },
      {
        assetType: AztecAssetType.ERC20,
        erc20Address: 'test',
        id: 1n,
      },
      {
        assetType: AztecAssetType.NOT_USED,
        erc20Address: AddressZero,
        id: 0n,
      },
      expiry,
    );
    expect(marketSize[0].assetId).toBe(BigInt(tokenAddress));
    expect(marketSize[0].amount).toBe(BigInt(tokenBalance));
    expect(marketSize.length).toBe(1);
  });
});
