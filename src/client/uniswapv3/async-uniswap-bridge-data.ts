import {
  AssetValue,
  AsyncYieldBridgeData,
  AuxDataConfig,
  AztecAsset,
  AztecAssetType,
  SolidityType,
} from '../bridge-data';
import { AsyncUniswapV3Bridge, AsyncUniswapV3Bridge__factory } from '../../../typechain-types';
import { BigNumber } from '@ethersproject/bignumber';
import { createWeb3Provider, EthereumProvider } from '../aztec/provider';
import { EthAddress } from '../aztec/eth_address';

export class AsyncUniswapBridgeData implements AsyncYieldBridgeData {
  private constructor(private bridgeContract: AsyncUniswapV3Bridge) {}

  static create(uniSwapAddress: EthAddress, provider: EthereumProvider) {
    return new AsyncUniswapBridgeData(
      AsyncUniswapV3Bridge__factory.connect(uniSwapAddress.toString(), createWeb3Provider(provider)),
    );
  }

  // @dev This function should be implemented for stateful bridges. It should return an array of AssetValue's
  // @dev which define how much a given interaction is worth in terms of Aztec asset ids.
  // @param bigint interactionNonce the interaction nonce to return the value for

  async getInteractionPresentValue(interactionNonce: bigint): Promise<AssetValue[]> {
    // we get the present value of the interaction
    const amounts = await this.bridgeContract.getPresentValue(interactionNonce);
    return [
      {
        assetId: interactionNonce,
        amount: BigInt(amounts[0].toBigInt()),
      },
      {
        assetId: interactionNonce,
        amount: BigInt(amounts[1].toBigInt()),
      },
    ];
  }

  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<bigint[]> {
    return [0n, 0n, 0n];
  }

  public auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 24,
      solidityType: SolidityType.uint24,
      description: 'tickLower',
    },

    {
      start: 0,
      length: 24,
      solidityType: SolidityType.uint24,
      description: 'tickLower',
    },

    {
      start: 48,
      length: 56,
      solidityType: SolidityType.uint8,
      description: 'fee',
    },

    {
      start: 56,
      length: 64,
      solidityType: SolidityType.uint8,
      description: 'expiry (in terms of days from now)',
    },
  ];

  async getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    precision: bigint,
  ): Promise<bigint[]> {
    // bridge is async the third parameter represents this
    return [BigInt(0), BigInt(0), BigInt(1)];
  }

  async getExpectedYearlyOuput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    precision: bigint,
  ): Promise<bigint[]> {
    //no interest for this bridge
    return [0n];
  }

  async getMarketSize(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
  ): Promise<AssetValue[]> {
    const WETH = '0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2';
    const zero = '0x0000000000000000000000000000000000000000';

    let inA = zero;
    let inB = zero;

    //gets the liquidity of the AMM pair in the tick range indicated by the provided auxData
    //the user should input the pairs via inputAssetA and inputAssetB , rather than
    //following the structure of the convert call they would actually take, since the limitations of
    //the convert call don't really matter here

    if (inputAssetA.assetType == AztecAssetType.ETH) {
      inA = WETH;
    } else if (inputAssetA.assetType == AztecAssetType.ERC20) {
      inA = inputAssetA.erc20Address;
    }

    if (inputAssetB.assetType == AztecAssetType.ETH) {
      inB = WETH;
    } else if (inputAssetB.assetType == AztecAssetType.ERC20) {
      inB = inputAssetB.erc20Address;
    }

    let balances = await this.bridgeContract.getLiquidity(inA, inB, BigNumber.from(auxData));

    return [
      {
        assetId:
          BigInt(inputAssetA.erc20Address) < BigInt(inputAssetB.erc20Address)
            ? BigInt(inputAssetA.erc20Address)
            : BigInt(inputAssetB.erc20Address),
        amount: balances[0].toBigInt(),
      },
      {
        assetId:
          BigInt(inputAssetA.erc20Address) < BigInt(inputAssetB.erc20Address)
            ? BigInt(inputAssetB.erc20Address)
            : BigInt(inputAssetA.erc20Address),
        amount: balances[1].toBigInt(),
      },
    ];
  }
  async getAuxDataLP(data: bigint[]): Promise<bigint[]> {
    let tickLower = BigNumber.from(data[0]);
    let tickUpper = BigNumber.from(data[1]);
    let fee = BigNumber.from(data[2]);
    let days = BigNumber.from(data[3]);

    const auxData = await this.bridgeContract.packData(tickLower, tickUpper, fee, days);

    return [auxData.toBigInt()];
  }

  async getExpiration(interactionNonce: bigint): Promise<bigint> {
    const expiry = await this.bridgeContract.getExpiry(interactionNonce);
    console.log(expiry);
    return BigInt(expiry.toBigInt());
  }

  async hasFinalised(interactionNonce: bigint): Promise<Boolean> {
    const finalised = await this.bridgeContract.finalised(interactionNonce);
    console.log(finalised);
    return finalised;
  }
}
