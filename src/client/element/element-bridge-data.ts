import { BridgeId } from '../aztec/bridge_id';
import { AddressZero } from '@ethersproject/constants';

import { AssetValue, AsyncYieldBridgeData, AuxDataConfig, AztecAsset, SolidityType } from '../bridge-data';
import { ElementBridge, RollupProcessor, IVault } from '../../../typechain-types';
import { AsyncDefiBridgeProcessedEvent } from '../../../typechain-types/RollupProcessor';

export type BatchSwapStep = {
  poolId: string;
  assetInIndex: number;
  assetOutIndex: number;
  amount: string;
  userData: string;
};

export enum SwapType {
  SwapExactIn,
  SwapExactOut,
}

export type FundManagement = {
  sender: string;
  recipient: string;
  fromInternalBalance: boolean;
  toInternalBalance: boolean;
};

export type ChainProperties = {
  chunkSize: number;
};

interface EventBlock {
  nonce: bigint;
  blockNumber: number;
  bridgeId: bigint;
  totalInputValue: bigint;
  timestamp: number;
}

function divide(a: bigint, b: bigint, precision: bigint) {
  return (a * precision) / b;
}

export class ElementBridgeData implements AsyncYieldBridgeData {
  private elementBridgeContract: ElementBridge;
  private rollupContract: RollupProcessor;
  private balancerContract: IVault;
  public scalingFactor = BigInt(1n * 10n ** 18n);
  private interactionBlockNumbers: Array<EventBlock> = [];

  constructor(
    elementBridge: ElementBridge,
    balancer: IVault,
    rollupContract: RollupProcessor,
    private chainProperties: ChainProperties = { chunkSize: 10000 },
  ) {
    this.elementBridgeContract = elementBridge;
    this.rollupContract = rollupContract;
    this.balancerContract = balancer;
  }

  private async storeEventBlocks(events: AsyncDefiBridgeProcessedEvent[]) {
    if (!events.length) {
      return;
    }
    const storeBlock = async (event: AsyncDefiBridgeProcessedEvent) => {
      const {
        args: [bridgeId, nonce, totalInputValue],
      } = event;
      const block = await event.getBlock();
      const newEventBlock = {
        nonce: nonce.toBigInt(),
        blockNumber: block.number,
        bridgeId: bridgeId.toBigInt(),
        totalInputValue: totalInputValue.toBigInt(),
        timestamp: block.timestamp,
      };
      const index = this.interactionBlockNumbers.findIndex(value => value.nonce > newEventBlock.nonce);
      this.interactionBlockNumbers.splice(index === -1 ? this.interactionBlockNumbers.length : index, 0, newEventBlock);
    };
    // store the first event and the last (if there are more than one)
    storeBlock(events[0]);
    if (events.length > 0) {
      storeBlock(events[events.length - 1]);
    }
  }

  private async findDefiEventForNonce(interactionNonce: bigint) {
    const storedBlock = this.interactionBlockNumbers.find(value => value.nonce === interactionNonce);
    if (storedBlock) {
      return storedBlock;
    }

    // start of with the earliest possible block being the block in which the tranche was first deployed
    let earliestBlock = await this.elementBridgeContract.getTrancheDeploymentBlockNumber(interactionNonce);
    // start with the last block being the current block
    let lastBlock = await this.elementBridgeContract.provider.getBlockNumber();
    // try and find a previously stored event with a nonce greater than ours
    const firstNonceAfterIndex = this.interactionBlockNumbers.findIndex(value => value.nonce > interactionNonce);

    // attempt to constrain the search using results from previous searches
    if (firstNonceAfterIndex !== -1) {
      // we have a previous stored event whose nonce is later than the one requested
      // so we only need to search back from there
      lastBlock = this.interactionBlockNumbers[firstNonceAfterIndex].blockNumber;
      if (
        firstNonceAfterIndex > 0 &&
        this.interactionBlockNumbers[firstNonceAfterIndex - 1].nonce < interactionNonce &&
        this.interactionBlockNumbers[firstNonceAfterIndex - 1].blockNumber > earliestBlock
      ) {
        // here, we have a previous stored event that has
        // a nonce that is less than that given
        // a block that is later than the tranche deployment block
        // so use this as the 'earliest' block
        earliestBlock = this.interactionBlockNumbers[firstNonceAfterIndex - 1].blockNumber;
      }
    }

    let end = lastBlock;
    let start = end - this.chainProperties.chunkSize;
    start = Math.max(start, earliestBlock);

    while (end > earliestBlock) {
      const events = await this.rollupContract.queryFilter(
        this.rollupContract.filters.AsyncDefiBridgeProcessed(undefined, interactionNonce),
        end,
        start,
      );
      // capture these event markers
      await this.storeEventBlocks(events);
      // there should just be one event, the one we are searching for. but to be sure we will process everything received
      for (const event of events) {
        const {
          args: [bridgeId, nonce, totalInputValue],
        } = event;
        if (nonce.toBigInt() === interactionNonce) {
          // this is our event so return it
          const block = await event.getBlock();
          const newEventBlock = {
            nonce: nonce.toBigInt(),
            blockNumber: block.number,
            bridgeId: bridgeId.toBigInt(),
            totalInputValue: totalInputValue.toBigInt(),
            timestamp: block.timestamp,
          };
          return newEventBlock;
        }
      }

      // if we didn't find an event then go round again but search further back in time
      end = start - 1;
      start = end - this.chainProperties.chunkSize;
      start = Math.max(start, earliestBlock);
    }
  }

  // @dev This function should be implemented for stateful bridges. It should return an array of AssetValue's
  // @dev which define how much a given interaction is worth in terms of Aztec asset ids.
  // @param bigint interactionNonce the interaction nonce to return the value for

  async getInteractionPresentValue(interactionNonce: bigint): Promise<AssetValue[]> {
    const interaction = await this.elementBridgeContract.interactions(interactionNonce);
    const exitTimestamp = interaction.expiry;
    const endValue = interaction.quantityPT;

    // we get the present value of the interaction
    const defiEvent = await this.findDefiEventForNonce(interactionNonce);
    if (defiEvent === undefined) {
      return [];
    }

    const now = Math.floor(Date.now() / 1000);
    const totalInterest = endValue.toBigInt() - defiEvent.totalInputValue;
    const elapsedTime = BigInt(now - defiEvent.timestamp);
    const totalTime = exitTimestamp.toBigInt() - BigInt(defiEvent.timestamp);
    const timeRatio = divide(elapsedTime, totalTime, this.scalingFactor);
    const accruedInterst = (totalInterest * timeRatio) / this.scalingFactor;

    return [
      {
        assetId: BigInt(BridgeId.fromBigInt(defiEvent.bridgeId).inputAssetId),
        amount: defiEvent.totalInputValue + accruedInterst,
      },
    ];
  }

  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<bigint[]> {
    return (await this.elementBridgeContract.getAssetExpiries(inputAssetA.erc20Address)).map(a => a.toBigInt());
  }

  public auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: 'Unix Timestamp of the tranch expiry',
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
    const assetExpiryHash = await this.elementBridgeContract.hashAssetAndExpiry(inputAssetA.erc20Address, auxData);
    const pool = await this.elementBridgeContract.pools(assetExpiryHash);
    const poolId = pool.poolId;
    const trancheAddress = pool.trancheAddress;

    const funds: FundManagement = {
      sender: AddressZero,
      recipient: AddressZero,
      fromInternalBalance: false,
      toInternalBalance: false,
    };

    const step: BatchSwapStep = {
      poolId,
      assetInIndex: 0,
      assetOutIndex: 1,
      amount: precision.toString(),
      userData: '0x',
    };

    const deltas = await this.balancerContract.queryBatchSwap(
      SwapType.SwapExactIn,
      [step],
      [inputAssetA.erc20Address, trancheAddress],
      funds,
    );

    const outputAssetAValue = deltas[1];

    const timeToExpiration = auxData - BigInt(Math.floor(Date.now() / 1000));

    const YEAR = 60n * 60n * 24n * 365n;
    const interest = -outputAssetAValue.toBigInt() - precision;
    const scaledOutput = divide(interest, timeToExpiration, this.scalingFactor);
    const yearlyOutput = (scaledOutput * YEAR) / this.scalingFactor;

    return [yearlyOutput + precision, BigInt(0)];
  }

  async getMarketSize(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
  ): Promise<AssetValue[]> {
    const assetExpiryHash = await this.elementBridgeContract.hashAssetAndExpiry(inputAssetA.erc20Address, auxData);
    const pool = await this.elementBridgeContract.pools(assetExpiryHash);
    const poolId = pool.poolId;
    const tokenBalances = await this.balancerContract.getPoolTokens(poolId);

    // todo return the correct aztec assetIds
    return tokenBalances[0].map((address, index) => {
      return {
        assetId: BigInt(address), // todo fetch via the sdk @Leila
        amount: tokenBalances[1][index].toBigInt(),
      };
    });
  }

  async getExpiration(interactionNonce: bigint): Promise<bigint> {
    const interaction = await this.elementBridgeContract.interactions(interactionNonce);

    return BigInt(interaction.expiry.toString());
  }

  async hasFinalised(interactionNonce: bigint): Promise<Boolean> {
    const interaction = await this.elementBridgeContract.interactions(interactionNonce);
    return interaction.finalised;
  }
}
