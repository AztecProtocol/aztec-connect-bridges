import { MStableBridgeData } from './mstable-bridge-data';
import { BigNumber, Signer } from 'ethers';
import { randomBytes } from 'crypto';
import { IRollupProcessor,IMStableSavingsContract, IMStableAsset, MStableBridge } from '../../../typechain-types';
import { AztecAssetType } from '../bridge-data';
import { AddressZero } from '@ethersproject/constants';

type Mockify<T> = {
  [P in keyof T]: jest.Mock;
};

const randomAddress = () => `0x${randomBytes(20).toString('hex')}`;

describe('element bridge data', () => {
  let rollupContract: Mockify<IRollupProcessor>;
  let mStableBridge: Mockify<MStableBridge>;
  let mStableAsset: Mockify<IMStableAsset>;
  let mStableSavingsContract: Mockify<IMStableSavingsContract>;

  it('should return the correct expected output for dai -> imUSD', async () => {
    const expiry = BigInt(Date.now() + 86400 * 30);
    const trancheAddress = '0x90ca5cef5b29342b229fb8ae2db5d8f4f894d652';
    const poolId = '0x90ca5cef5b29342b229fb8ae2db5d8f4f894d6520002000000000000000000b5';
    const exchangeRateOutput = 100000n;
    const inputValue = 10e18,
      mStableBridge = {
        hashAssetAndExpiry: jest.fn().mockResolvedValue('0xa'),
        pools: jest.fn().mockResolvedValue([trancheAddress, '', poolId]),
      };

    mStableAsset = {
      ...mStableAsset,
      getMintOutput: jest.fn().mockImplementation((...args) => {
        const amount = args[0]
        return Promise.resolve([BigNumber.from(BigInt(amount))]);
      }),
    };

    mStableSavingsContract = {
      ...mStableSavingsContract,
      exchangeRate: jest.fn().mockImplementation((...args) => {
        return Promise.resolve([BigNumber.from(BigInt(exchangeRateOutput))]);
      }),
    };

    const mStableBridgeData = new MStableBridgeData(
      mStableBridge as any,
      mStableSavingsContract as any,
      rollupContract as any,
      mStableAsset as any,
    );
    const output = await mStableBridgeData.getExpectedOutput(
      {
        assetType: AztecAssetType.ERC20,
        erc20Address: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
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
    const timeToExpiration = expiry - BigInt(Date.now());
    const scaledOut = (BigInt(exchangeRateOutput) * mStableBridgeData.scalingFactor) / timeToExpiration;
    const yearlyOut = (scaledOut * BigInt(YEAR)) / mStableBridgeData.scalingFactor;

    expect(output[0]).toBe(6113822868316214672338877989218439360196540n);
  });

  it('should return the correct expected output for imUSD -> dai', async () => {
    const expiry = BigInt(Date.now() + 86400 * 30);
    const trancheAddress = '0x90ca5cef5b29342b229fb8ae2db5d8f4f894d652';
    const poolId = '0x90ca5cef5b29342b229fb8ae2db5d8f4f894d6520002000000000000000000b5';
    const exchangeRateOutput = 611382286831621467233887798921843936019654057231n;
    const inputValue = 10e18,
      mStableBridge = {
        hashAssetAndExpiry: jest.fn().mockResolvedValue('0xa'),
        pools: jest.fn().mockResolvedValue([trancheAddress, '', poolId]),
      };

    mStableAsset = {
      ...mStableAsset,
      getRedeemOutput: jest.fn().mockImplementation((...args) => {
        const amount = args[0]
        return Promise.resolve([BigNumber.from(BigInt(amount))]);
      }),
    };

    mStableSavingsContract = {
      ...mStableSavingsContract,
      exchangeRate: jest.fn().mockImplementation((...args) => {
        return Promise.resolve([BigNumber.from(BigInt(exchangeRateOutput))]);
      }),
    };

    const mStableBridgeData = new MStableBridgeData(
      mStableBridge as any,
      mStableSavingsContract as any,
      rollupContract as any,
      mStableAsset as any,
    );
    const output = await mStableBridgeData.getExpectedOutput(
      {
        assetType: AztecAssetType.ERC20,
        erc20Address: '',
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
    const timeToExpiration = expiry - BigInt(Date.now());
    const scaledOut = (BigInt(exchangeRateOutput) * mStableBridgeData.scalingFactor) / timeToExpiration;
    const yearlyOut = (scaledOut * BigInt(YEAR)) / mStableBridgeData.scalingFactor;

    expect(output[0]).toBe(373788300651463064139851103108934879838140924198069817386268142465257177628774884397639423387361n);
  });


  it('should return the correct yearly output', async () => {
    const expiry = BigInt(Date.now() + 86400 * 30);
    const trancheAddress = '0x90ca5cef5b29342b229fb8ae2db5d8f4f894d652';
    const poolId = '0x90ca5cef5b29342b229fb8ae2db5d8f4f894d6520002000000000000000000b5';
    const exchangeRateOutput = 100000n;
    const inputValue = 10e18,
      mStableBridge = {
        hashAssetAndExpiry: jest.fn().mockResolvedValue('0xa'),
        pools: jest.fn().mockResolvedValue([trancheAddress, '', poolId]),
      };

    const mStableBridgeData = new MStableBridgeData(
      mStableBridge as any,
      mStableAsset as any,
      mStableSavingsContract as any,
      rollupContract as any,
    );
    const output = await mStableBridgeData.getExpectedYearlyOuput(
      {
        assetType: AztecAssetType.ERC20,
        erc20Address: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
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
    const timeToExpiration = expiry - BigInt(Date.now());
    const scaledOut = (BigInt(exchangeRateOutput) * mStableBridgeData.scalingFactor) / timeToExpiration;
    const yearlyOut = (scaledOut * BigInt(YEAR)) / mStableBridgeData.scalingFactor;

    expect(output[0]).toBeGreaterThan(1);
  });
});