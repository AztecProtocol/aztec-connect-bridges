import { BridgeId } from '../aztec/bridge_id';
import { AddressZero } from '@ethersproject/constants';
import { AssetValue, AsyncYieldBridgeData, AuxDataConfig, AztecAsset, SolidityType } from '../bridge-data';
import {
  ElementBridge,
  IVault,
  RollupProcessor,
  ElementBridge__factory,
  IVault__factory,
  RollupProcessor__factory,
} from '../../../typechain-types';
import { AsyncDefiBridgeProcessedEvent } from '../../../typechain-types/RollupProcessor';
import { EthereumProvider } from '../aztec/provider/ethereum_provider';
import { createWeb3Provider } from '../aztec/provider/';

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

// Some operations on this class require us to scan back over the blockchain
// to find published events. This is done in batches of blocks. The chunk size in this set of properties
// determines how many blocks to request in each batch.
// Users of this class can customise this to their provider requirements
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

const decodeEvent = async (event: AsyncDefiBridgeProcessedEvent) => {
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
  return newEventBlock;
};

export class ElementBridgeData implements AsyncYieldBridgeData {
  public scalingFactor = BigInt(1n * 10n ** 18n);
  private interactionBlockNumbers: Array<EventBlock> = [];

  private constructor(
    private elementBridgeContract: ElementBridge,
    private balancerContract: IVault,
    private rollupContract: RollupProcessor,
    private chainProperties: ChainProperties,
  ) {}

  static create(
    provider: EthereumProvider,
    elementBridgeAddress: string,
    balancerAddress: string,
    rollupContractAddress: string,
    chainProperties: ChainProperties = { chunkSize: 10000 },
  ) {
    const ethersProvider = createWeb3Provider(provider);
    const elementBridgeContract = ElementBridge__factory.connect(elementBridgeAddress, ethersProvider);
    const rollupContract = RollupProcessor__factory.connect(rollupContractAddress, ethersProvider);
    const vaultContract = IVault__factory.connect(balancerAddress, ethersProvider);
    return new ElementBridgeData(elementBridgeContract, vaultContract, rollupContract, chainProperties);
  }

  private async storeEventBlocks(events: AsyncDefiBridgeProcessedEvent[]) {
    if (!events.length) {
      return;
    }
    const storeBlock = async (event: AsyncDefiBridgeProcessedEvent) => {
      const newEventBlock = await decodeEvent(event);
      for (let i = 0; i < this.interactionBlockNumbers.length; i++) {
        const currentBlock = this.interactionBlockNumbers[i];
        if (currentBlock.nonce === newEventBlock.nonce) {
          return;
        }
        if (currentBlock.nonce > newEventBlock.nonce) {
          this.interactionBlockNumbers.splice(i, 0, newEventBlock);
          return;
        }
      }
      this.interactionBlockNumbers.push(newEventBlock);
    };
    // store the first event and the last (if there are more than one)
    await storeBlock(events[0]);
    if (events.length > 1) {
      await storeBlock(events[events.length - 1]);
    }
  }

  private async getCurrentBlock() {
    const currentBlockNumber = await this.elementBridgeContract.provider.getBlockNumber();
    const currentBlock = await this.elementBridgeContract.provider.getBlock(currentBlockNumber);
    return currentBlock;
  }

  private async findDefiEventForNonce(interactionNonce: bigint) {
    // start off with the earliest possible block being the block in which the tranche was first deployed
    let earliestBlockNumber = Number(
      await this.elementBridgeContract.getTrancheDeploymentBlockNumber(interactionNonce),
    );
    // start with the last block being the current block
    let lastBlock = await this.getCurrentBlock();
    let latestBlockNumber = lastBlock.number;
    // try and find previously stored events that encompass the nonce we are looking for
    // also if we find the exact nonce then just return the stored data
    for (let i = 0; i < this.interactionBlockNumbers.length; i++) {
      const storedBlock = this.interactionBlockNumbers[i];
      if (storedBlock.nonce == interactionNonce) {
        return storedBlock;
      }
      if (storedBlock.nonce < interactionNonce) {
        earliestBlockNumber = storedBlock.blockNumber;
      }
      if (storedBlock.nonce > interactionNonce) {
        // this is the first block beyond the one we are looking for, we can break here
        latestBlockNumber = storedBlock.blockNumber;
        break;
      }
    }

    let end = latestBlockNumber;
    let start = end - (this.chainProperties.chunkSize - 1);
    start = Math.max(start, earliestBlockNumber);

    while (end > earliestBlockNumber) {
      const events = await this.rollupContract.queryFilter(
        this.rollupContract.filters.AsyncDefiBridgeProcessed(undefined, interactionNonce),
        start,
        end,
      );
      // capture these event markers
      await this.storeEventBlocks(events);
      // there should just be one event, the one we are searching for. but to be sure we will process everything received
      for (const event of events) {
        const newEventBlock = await decodeEvent(event);
        if (newEventBlock.nonce == interactionNonce) {
          return newEventBlock;
        }
      }

      // if we didn't find an event then go round again but search further back in time
      end = start - 1;
      start = end - (this.chainProperties.chunkSize - 1);
      start = Math.max(start, earliestBlockNumber);
    }
  }

  // @dev This function should be implemented for stateful bridges. It should return an array of AssetValue's
  // @dev which define how much a given interaction is worth in terms of Aztec asset ids.
  // @param bigint interactionNonce the interaction nonce to return the value for

  async getInteractionPresentValue(interactionNonce: bigint): Promise<AssetValue[]> {
    const interaction = await this.elementBridgeContract.interactions(interactionNonce);
    if (interaction === undefined) {
      return [];
    }
    const exitTimestamp = interaction.expiry;
    const endValue = interaction.quantityPT;

    // we get the present value of the interaction
    const defiEvent = await this.findDefiEventForNonce(interactionNonce);
    if (defiEvent === undefined) {
      return [];
    }

    const latestBlock = await this.getCurrentBlock();

    const now = latestBlock.timestamp;
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

    const latestBlock = await this.getCurrentBlock();

    const outputAssetAValue = deltas[1];

    const timeToExpiration = auxData - BigInt(latestBlock.timestamp);

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
