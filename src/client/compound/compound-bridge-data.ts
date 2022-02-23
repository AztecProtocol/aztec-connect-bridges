import { AssetValue, AuxDataConfig, AztecAsset, BridgeData, SolidityType } from '../bridge-data';

interface ICERC20 {
  function accrueInterest() external;
  function approve(address, uint) external returns (uint);
  function balanceOf(address) external view returns (uint256);
  function balanceOfUnderlying(address) external view returns (uint256);
  function exchangeRateStored() external view returns (uint256);
  function transfer(address,uint) external returns (uint);
  function mint(uint256) external returns (uint256);
  function redeem(uint) external returns (uint);
  function redeemUnderlying(uint) external returns (uint);
  function underlying() external returns (address);
}

export class CompoundBridgeData implements AsyncYieldBridgeData {
  private compoundBridgeContract: CompoundBridge;
  private rollupContract: RollupProcessor;
  public scalingFactor = 1000000000n;

  constructor(compoundBridge: CompoundBridge, rollupContract: RollupProcessor) {
    this.compoundBridgeContract = compoundBridge;
    this.rollupContract = rollupContract;
  }

  // @dev This function should be implemented for stateful bridges. It should return an array of AssetValue's
  // @dev which define how much a given interaction is worth in terms of Aztec asset ids.
  // @param bigint interactionNonce the interaction nonce to return the value for

  async getInteractionPresentValue(interactionNonce: bigint): Promise<AssetValue[]> {
    const interaction = await this.compoundBridgeContract.interactions(interactionNonce);
    const [rollupInteraction] = await this.rollupContract.queryFilter(
      this.rollupContract.filters.DefiBridgeProcessed(interactionNonce),
    );
    const { timestamp: entryTimestamp } = await rollupInteraction.getBlock();
    const {
      args: [bridgeId, , totalInputValue],
    } = rollupInteraction;

    const now = Date.now();
    const totalInterest = endValue.toBigInt() - totalInputValue.toBigInt();
    const elapsedTime = BigInt(now - entryTimestamp);
    const totalTime = exitTimestamp.toBigInt() - BigInt(entryTimestamp);
    return [
      {
        assetId: BigInt(BridgeId.fromBigInt(bridgeId.toBigInt()).inputAssetId),
        amount:
          totalInputValue.toBigInt() +
          (totalInterest * (((elapsedTime * this.scalingFactor) / totalTime) * this.scalingFactor)) /
            this.scalingFactor,
      },
    ];
  }
  }

  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<bigint[]> {
    return [0n];
  }

  public auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: 'Encodes the type of interaction with Compound markets: 0 = mint, 1 = redeem, 2 = borrow, 3 = repay',
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
    return [0n, 0n, 1n];
  }

  async getExpectedYearlyOuput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    precision: bigint,
  ): Promise<bigint[]> {

    const ethMantissa = 1e18;
    const blocksPerDay = 6570;
    const daysPerYear = 365;

    // Return the supply APY
    const supplyRatePerBlock = await ICERC20(outputAssetA.erc20address).supplyRatePerBlock();
    const supplyAPY = (((((supplyRatePerBlock / ethMantissa * blocksPerDay) + 1)**( daysPerYear))) - 1) * 100;
    return [supplyAPY, 0n];
  }

  // ATC: unclear whether this should return supply market size or size of total enter/exit in rollup
  async getMarketSize(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
  ): Promise<AssetValue[]> {
    return [{ assetId: 0n, amount: 100n }];
  }
}
