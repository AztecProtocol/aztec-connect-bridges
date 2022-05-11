import { AsyncUniswapBridgeData } from './async-uniswap-bridge-data';
import { SyncUniswapBridgeData } from './uniswap-bridge-data';
import { BigNumber } from 'ethers';
import {
  SyncUniswapV3Bridge,
  AsyncUniswapV3Bridge,
  SyncUniswapV3Bridge__factory,
  AsyncUniswapV3Bridge__factory,
} from '../../../typechain-types';
import { AztecAsset, AztecAssetType } from '../bridge-data';
import { AddressZero } from '@ethersproject/constants';
import { defaultAbiCoder } from '@ethersproject/abi';
import { EthAddress } from '@aztec/barretenberg/address';
//import '@types/jest';

jest.mock('../aztec/provider', () => ({
  createWeb3Provider: jest.fn(),
}));

type Mockify<T> = {
  [P in keyof T]: jest.Mock;
};

describe('sync bridge data && async bridge data', () => {
  let syncBridgeData: SyncUniswapBridgeData;
  let asyncBridgeData: AsyncUniswapBridgeData;
  let syncBridge: Mockify<SyncUniswapV3Bridge>;
  let asyncBridge: Mockify<AsyncUniswapV3Bridge>;

  let ethAsset: AztecAsset;
  let DAI: AztecAsset;
  let WETH: AztecAsset;
  let emptyAsset: AztecAsset;
  let virtualAsset: AztecAsset;

  const createSyncBridgeData = (bridge: SyncUniswapV3Bridge = syncBridge as any) => {
    SyncUniswapV3Bridge__factory.connect = () => bridge as any;
    return SyncUniswapBridgeData.create(EthAddress.ZERO, {} as any); // can pass in dummy values here as the above factories do all of the work
  };

  const createASyncBridgeData = (bridge: AsyncUniswapV3Bridge = syncBridge as any) => {
    AsyncUniswapV3Bridge__factory.connect = () => bridge as any;
    return AsyncUniswapBridgeData.create(EthAddress.ZERO, {} as any); // can pass in dummy values here as the above factories do all of the work
  };

  beforeAll(() => {
    ethAsset = {
      id: 1n,
      assetType: AztecAssetType.ETH,
      erc20Address: AddressZero,
    };
    DAI = {
      id: 2n,
      assetType: AztecAssetType.ERC20,
      erc20Address: '0x6B175474E89094C44Da98b954EedeAC495271d0F',
    };
    WETH = {
      id: 2n,
      assetType: AztecAssetType.ERC20,
      erc20Address: '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2',
    };

    emptyAsset = {
      id: 0n,
      assetType: AztecAssetType.NOT_USED,
      erc20Address: AddressZero,
    };
    virtualAsset = {
      id: 2n,
      assetType: AztecAssetType.VIRTUAL,
      erc20Address: AddressZero,
    };
  });

  it('should return market liquidity', async () => {
    syncBridge = {
      ...syncBridge,
      getLiquidity: jest.fn().mockResolvedValue([BigNumber.from(100), BigNumber.from(100)]),
    };

    syncBridgeData = createSyncBridgeData(syncBridge as any);

    const output = await syncBridgeData.getMarketSize(WETH, DAI, emptyAsset, emptyAsset, 0n);

    expect(100n == output[0].amount && 100n == output[1].amount).toBeTruthy();
  });
  it('should get presentvalue', async () => {
    syncBridge = {
      ...syncBridge,
      getPresentValue: jest.fn().mockResolvedValue([BigNumber.from(1000), BigNumber.from(1000)]),
    };

    syncBridgeData = createSyncBridgeData(syncBridge as any);

    const output = await syncBridgeData.getInteractionPresentValue(BigInt(1));
    expect(1000n == output[0].amount && 1000n == output[1].amount).toBeTruthy();
  });
  it('should get the expected output', async () => {
    const depositAmount = 1000n;
    const out0 = BigInt(1000n);
    const out1 = BigInt(1000n);
    let abicoder = defaultAbiCoder;
    let mockData = abicoder.encode(['uint256', 'uint256', 'bool'], [out0, out1, false]);
    //we encode 100 and 100
    syncBridge = {
      ...syncBridge,
      staticcall: jest.fn().mockResolvedValue(mockData),
    };

    syncBridgeData = createSyncBridgeData(syncBridge as any);

    const output = await syncBridgeData.getExpectedOutput(
      WETH,
      emptyAsset,
      virtualAsset,
      emptyAsset,
      0n,
      depositAmount,
    );

    expect(out0 == output[0] && out1 == output[1]).toBeTruthy();
  });

  it('should correctly return the auxData', async () => {
    syncBridge = {
      ...syncBridge,
      packData: jest.fn().mockResolvedValue(BigNumber.from(300000)),
    };

    syncBridgeData = createSyncBridgeData(syncBridge as any);
    let data = [100n, 100n, 100n];
    const output = await syncBridgeData.getAuxDataLP(data);

    expect(output[0]).toBe(300000n);
  });

  //asyncBridge
  it('should return market liquidity', async () => {
    asyncBridge = {
      ...asyncBridge,
      getLiquidity: jest.fn().mockResolvedValue([BigNumber.from(100), BigNumber.from(100)]),
    };

    asyncBridgeData = createASyncBridgeData(asyncBridge as any);

    const output = await asyncBridgeData.getMarketSize(WETH, DAI, emptyAsset, emptyAsset, 0n);

    expect(100n == output[0].amount && 100n == output[1].amount).toBeTruthy();
  });

  it('should get presentvalue', async () => {
    asyncBridge = {
      ...asyncBridge,
      getPresentValue: jest.fn().mockResolvedValue([BigNumber.from(100), BigNumber.from(100)]),
    };

    asyncBridgeData = createASyncBridgeData(asyncBridge as any);

    const output = await asyncBridgeData.getInteractionPresentValue(BigInt(1));
    expect(output[0].amount == BigInt(100) && output[1].amount == BigInt(100)).toBeTruthy();
  });
  it('should get the expiration', async () => {
    const interactionNonce = 100n;

    asyncBridge = {
      ...asyncBridge,
      getExpiry: jest.fn().mockResolvedValue(BigNumber.from(1000n)),
    };

    asyncBridgeData = createASyncBridgeData(asyncBridge as any);

    const output = await asyncBridgeData.getExpiration(interactionNonce);

    expect(1000n == output).toBeTruthy();
  });

  it('should correctly return the auxData', async () => {
    asyncBridge = {
      ...asyncBridge,
      packData: jest.fn().mockResolvedValue(BigNumber.from(300000n)),
    };
    //tickLower, tickUpper, fee, days
    let data = [100n, 100n, 100n, 100n];
    asyncBridgeData = createASyncBridgeData(asyncBridge as any);
    const output = await asyncBridgeData.getAuxDataLP(data);

    expect(output[0]).toBe(300000n);
  });

  it('should correctly check finalisability', async () => {
    const interactionNonce = 1000n;

    asyncBridge = {
      ...asyncBridge,
      finalised: jest.fn().mockResolvedValue(true),
    };

    asyncBridgeData = createASyncBridgeData(asyncBridge as any);
    const output = await asyncBridgeData.hasFinalised(interactionNonce);

    expect(output).toBe(true);
  });
});
