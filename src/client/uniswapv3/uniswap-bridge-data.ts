import { AssetValue, AuxDataConfig, AztecAsset, AztecAssetType, BridgeData, SolidityType } from '../bridge-data';
import { SyncUniswapV3Bridge, SyncUniswapV3Bridge__factory } from '../../../typechain-types';
import { defaultAbiCoder, Interface } from '@ethersproject/abi';
import { BigNumber } from 'ethers';
import { createWeb3Provider, EthereumProvider } from '../aztec/provider';
import { EthAddress } from '../aztec/eth_address';

export class SyncUniswapBridgeData implements BridgeData {
  private constructor(private bridgeContract: SyncUniswapV3Bridge) {}

  static create(uniSwapAddress: EthAddress, provider: EthereumProvider) {
    return new SyncUniswapBridgeData(
      SyncUniswapV3Bridge__factory.connect(uniSwapAddress.toString(), createWeb3Provider(provider)),
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

  /*
  @dev This function should be implemented for all bridges that use auxData that require onchain data. It's purpose is to tell the developer using the bridge
  @dev the set of possible auxData's that they can use for a given set of inputOutputAssets.
  */

  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<bigint[]> {
    return [0n];
  }

  async getAuxDataLP(data: bigint[]): Promise<bigint[]> {
    let tickLower = BigNumber.from(data[0]);
    let tickUpper = BigNumber.from(data[1]);
    let fee = BigNumber.from(data[2]);
    const auxData = await this.bridgeContract.packData(tickLower, tickUpper, fee);

    return [auxData.toBigInt()];
  }

  public auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 24,
      solidityType: SolidityType.uint24,
      description: 'tickLower',
    },
    {
      start: 24,
      length: 24,
      solidityType: SolidityType.uint24,
      description: 'tickUpper',
    },
    {
      start: 48,
      length: 16,
      solidityType: SolidityType.uint16,
      description: 'fee',
    },
  ];

  enumToInt(inputAsset: AztecAsset): bigint {
    if (inputAsset.assetType == AztecAssetType.ETH) {
      return BigInt(1);
    } else if (inputAsset.assetType == AztecAssetType.ERC20) {
      return BigInt(2);
    } else if (inputAsset.assetType == AztecAssetType.VIRTUAL) {
      return BigInt(3);
    } else if (inputAsset.assetType == AztecAssetType.NOT_USED) {
      return BigInt(4);
    } else if (inputAsset == undefined || inputAsset == null) {
      return BigInt(5);
    }
    return BigInt(1);
  }

  async getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    precision: bigint,
  ): Promise<bigint[]> {
    //substitute uint8 for enum due to ethers limitations

    let ABI = [
      'function convert( tuple(uint256 id,address erc20Address,uint8 assetType) inputAssetA, tuple(uint256 id,address erc20Address,uint8 assetType) inputAssetB,tuple(uint256 id,address erc20Address,uint8 assetType) outputAssetA,tuple(uint256 id,address erc20Address,uint8 assetType) outputAssetB,uint256 inputValue,uint256 interactionNonce,uint64 auxData)',
    ];
    let iface = new Interface(ABI);
    let inA = this.enumToInt(inputAssetA);
    let inB = this.enumToInt(inputAssetB);
    let outA = this.enumToInt(outputAssetA);
    let outB = this.enumToInt(outputAssetB);

    let calldata = iface.encodeFunctionData('convert', [
      {
        id: BigNumber.from(inputAssetA.id),
        assetType: BigNumber.from(inA),
        erc20Address: inputAssetA.erc20Address,
      },
      {
        id: BigNumber.from(inputAssetB.id),
        assetType: BigNumber.from(inB),
        erc20Address: inputAssetB.erc20Address,
      },
      {
        id: BigNumber.from(outputAssetA.id),
        assetType: BigNumber.from(outA),
        erc20Address: outputAssetA.erc20Address,
      },
      {
        id: BigNumber.from(outputAssetB.id),
        assetType: BigNumber.from(outB),
        erc20Address: outputAssetB.erc20Address,
      },
      BigNumber.from(precision),
      BigNumber.from(1),
      BigNumber.from(auxData),
    ]);
    //console.log(payload)
    iface = new Interface(['function staticcall(address _to, bytes calldata _data) returns (bytes memory)']);
    const data = await this.bridgeContract.staticcall(this.bridgeContract.address, calldata);
    let abiCoder = defaultAbiCoder;
    const convertOutput = await abiCoder.decode(['uint256', 'uint256', 'bool'], data);
    return [convertOutput[0], convertOutput[1]];
  }

  async getExpectedYearlyOuput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    precision: bigint,
  ): Promise<bigint[]> {
    //this bridge is synchronous
    //return 0 or else return getExpectedOutput()
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
}
