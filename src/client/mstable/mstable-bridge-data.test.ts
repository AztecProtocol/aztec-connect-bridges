import { MStableBridgeData } from './mstable-bridge-data';
import { BigNumber } from 'ethers';
import {
  IMStableSavingsContract,
  IMStableAsset,
  IMStableAsset__factory,
  IMStableSavingsContract__factory,
} from '../../../typechain-types';
import { AztecAssetType } from '../bridge-data';
import { AddressZero } from '@ethersproject/constants';

jest.mock('../aztec/provider', () => ({
  createWeb3Provider: jest.fn(),
}));

type Mockify<T> = {
  [P in keyof T]: jest.Mock;
};

describe('mstable bridge data', () => {
  let mStableAsset: Mockify<IMStableAsset>;
  let mStableSavingsContract: Mockify<IMStableSavingsContract>;

  const createMStableBridgeData = (
    asset: IMStableAsset = mStableAsset as any,
    savings: IMStableSavingsContract = mStableSavingsContract as any,
  ) => {
    IMStableAsset__factory.connect = () => asset as any;
    IMStableSavingsContract__factory.connect = () => savings as any;
    return MStableBridgeData.create({} as any, '', ''); // can pass in dummy values here as the above factories do all of the work
  };

  it('should return the correct expected output for dai -> imUSD', async () => {
    const exchangeRateOutput = 116885615338892891n;
    const inputValue = 10e18;
    mStableAsset = {
      ...mStableAsset,
      getMintOutput: jest.fn().mockImplementation((...args) => {
        const amount = args[1];
        return Promise.resolve(BigNumber.from(BigInt(amount)));
      }),
    } as any;

    mStableSavingsContract = {
      ...mStableSavingsContract,
      exchangeRate: jest.fn().mockImplementation((...args) => {
        return Promise.resolve(BigNumber.from(BigInt(exchangeRateOutput)));
      }),
    };

    const mStableBridgeData = createMStableBridgeData(mStableAsset as any, mStableSavingsContract as any);
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
    const inputValue = 10e18;
    mStableAsset = {
      ...mStableAsset,
      getRedeemOutput: jest.fn().mockImplementation((...args) => {
        const amount = args[1];
        return Promise.resolve(BigNumber.from(BigInt(amount)));
      }),
    } as any;

    mStableSavingsContract = {
      ...mStableSavingsContract,
      exchangeRate: jest.fn().mockImplementation((...args) => {
        return Promise.resolve(BigNumber.from(BigInt(exchangeRateOutput)));
      }),
    };

    const mStableBridgeData = createMStableBridgeData(mStableAsset as any, mStableSavingsContract as any);
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

  // it('should return the correct yearly output', async () => {
  //   const exchangeRateOutput = 116885615338892891n;
  //   const inputValue = 10e18;
  //   mStableAsset = {
  //     ...mStableAsset,
  //     getRedeemOutput: jest.fn().mockImplementation((...args) => {
  //       const amount = args[0];
  //       return Promise.resolve(BigNumber.from(BigInt(amount)));
  //     }),
  //   };

  //   mStableSavingsContract = {
  //     ...mStableSavingsContract,
  //     exchangeRate: jest.fn().mockImplementation((...args) => {
  //       return Promise.resolve(BigNumber.from(BigInt(exchangeRateOutput)));
  //     }),
  //   };
  //   const mStableBridgeData = createMStableBridgeData(mStableAsset as any, mStableSavingsContract as any);
  //   const output = await mStableBridgeData.getExpectedYearlyOuput(
  //     {
  //       assetType: AztecAssetType.ERC20,
  //       erc20Address: '0x30647a72dc82d7fbb1123ea74716ab8a317eac19',
  //       id: 1n,
  //     },
  //     {
  //       assetType: AztecAssetType.NOT_USED,
  //       erc20Address: AddressZero,
  //       id: 0n,
  //     },
  //     {
  //       assetType: AztecAssetType.ERC20,
  //       erc20Address: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
  //       id: 1n,
  //     },
  //     {
  //       assetType: AztecAssetType.NOT_USED,
  //       erc20Address: AddressZero,
  //       id: 0n,
  //     },
  //     50n,
  //     BigInt(inputValue),
  //   );

  //   expect(output[0]).toBeGreaterThan(inputValue);
  // });
});
