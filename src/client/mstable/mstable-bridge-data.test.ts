import { MStableBridgeData } from './mstable-bridge-data';
import { BigNumber, Signer } from 'ethers';
import { randomBytes } from 'crypto';
import { IRollupProcessor, IMStableSavingsContract, IMStableAsset, MStableBridge } from '../../../typechain-types';
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
    const exchangeRateOutput = 116885615338892891n;
    const inputValue = 10e18,
      mStableBridge = {};

    mStableAsset = {
      ...mStableAsset,
      getMintOutput: jest.fn().mockImplementation((...args) => {
        const amount = args[1];
        return Promise.resolve(BigNumber.from(BigInt(amount)));
      }),
    };

    mStableSavingsContract = {
      ...mStableSavingsContract,
      exchangeRate: jest.fn().mockImplementation((...args) => {
        return Promise.resolve(BigNumber.from(BigInt(exchangeRateOutput)));
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
      50n,
      BigInt(inputValue),
    );

    expect(output[0]).toBe(85553726786n);
  });

  it('should return the correct expected output for imUSD -> dai', async () => {
    const exchangeRateOutput = 116885615338892891n;
    const inputValue = 10e18,
      mStableBridge = {};

    mStableAsset = {
      ...mStableAsset,
      getRedeemOutput: jest.fn().mockImplementation((...args) => {
        const amount = args[1];
        return Promise.resolve(BigNumber.from(BigInt(amount)));
      }),
    };

    mStableSavingsContract = {
      ...mStableSavingsContract,
      exchangeRate: jest.fn().mockImplementation((...args) => {
        return Promise.resolve(BigNumber.from(BigInt(exchangeRateOutput)));
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
      50n,
      BigInt(inputValue),
    );

    expect(output[0]).toBe(1168856153388928910000000000000000000n);
  });

  it('should return the correct yearly output', async () => {
    const exchangeRateOutput = 116885615338892891n;
    const inputValue = 10e18;
    mStableAsset = {
      ...mStableAsset,
      getRedeemOutput: jest.fn().mockImplementation((...args) => {
        const amount = args[0];
        return Promise.resolve(BigNumber.from(BigInt(amount)));
      }),
    };

    mStableSavingsContract = {
      ...mStableSavingsContract,
      exchangeRate: jest.fn().mockImplementation((...args) => {
        return Promise.resolve(BigNumber.from(BigInt(exchangeRateOutput)));
      }),
    };
    const mStableBridgeData = new MStableBridgeData(
      mStableBridge as any,
      mStableSavingsContract as any,
      rollupContract as any,
      mStableAsset as any,
    );
    const output = await mStableBridgeData.getExpectedYearlyOuput(
      {
        assetType: AztecAssetType.ERC20,
        erc20Address: '0x30647a72dc82d7fbb1123ea74716ab8a317eac19',
        id: 1n,
      },
      {
        assetType: AztecAssetType.NOT_USED,
        erc20Address: AddressZero,
        id: 0n,
      },
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
      50n,
      BigInt(inputValue),
    );

    expect(output[0]).toBeGreaterThan(inputValue);
  });
});
