import { AssetValue, BridgeDataFieldGetters, AuxDataConfig, AztecAsset, SolidityType } from "../bridge-data";
import {
  ElementBridge,
  IVault,
  IRollupProcessor,
  ElementBridge__factory,
  IVault__factory,
  IRollupProcessor__factory,
} from "../../../typechain-types";
import { AsyncDefiBridgeProcessedEvent } from "../../../typechain-types/IRollupProcessor";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { createWeb3Provider } from "../aztec/provider";
import { EthAddress } from "@aztec/barretenberg/address";
// TODO: simply import BridgeCallData once the name is changed on defi-bridge-project
import { BridgeId as BridgeCallData } from "@aztec/barretenberg/bridge_id";

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
// to find published events. This is done in batches of blocks. The batch size in this set of properties
// determines how many blocks to request in each batch.
// Users of this class can customise this to their provider requirements
export type ChainProperties = {
  eventBatchSize: number;
};

interface EventBlock {
  nonce: bigint;
  blockNumber: number;
  encodedBridgeCallData: bigint;
  totalInputValue: bigint;
  timestamp: number;
}

function divide(a: bigint, b: bigint, precision: bigint) {
  return (a * precision) / b;
}

const decodeEvent = async (event: AsyncDefiBridgeProcessedEvent): Promise<EventBlock> => {
  const {
    args: [encodedBridgeCallData, nonce, totalInputValue],
  } = event;
  const block = await event.getBlock();
  const newEventBlock = {
    nonce: nonce.toBigInt(),
    blockNumber: block.number,
    encodedBridgeCallData: encodedBridgeCallData.toBigInt(),
    totalInputValue: totalInputValue.toBigInt(),
    timestamp: block.timestamp,
  };
  return newEventBlock;
};

export class ElementBridgeData implements BridgeDataFieldGetters {
  public scalingFactor = BigInt(1n * 10n ** 18n);
  private interactionBlockNumbers: Array<EventBlock> = [];

  private constructor(
    private elementBridgeContract: ElementBridge,
    private balancerContract: IVault,
    private rollupContract: IRollupProcessor,
    private chainProperties: ChainProperties,
  ) {}

  static create(
    provider: EthereumProvider,
    elementBridgeAddress: EthAddress,
    balancerAddress: EthAddress,
    rollupContractAddress: EthAddress,
    chainProperties: ChainProperties = { eventBatchSize: 10000 },
  ) {
    const ethersProvider = createWeb3Provider(provider);
    const elementBridgeContract = ElementBridge__factory.connect(elementBridgeAddress.toString(), ethersProvider);
    const rollupContract = IRollupProcessor__factory.connect(rollupContractAddress.toString(), ethersProvider);
    const vaultContract = IVault__factory.connect(balancerAddress.toString(), ethersProvider);
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
    return this.elementBridgeContract.provider.getBlock("latest");
  }

  private async findDefiEventForNonce(interactionNonce: bigint) {
    // start off with the earliest possible block being the block in which the tranche was first deployed
    let earliestBlockNumber = Number(
      await this.elementBridgeContract.getTrancheDeploymentBlockNumber(interactionNonce),
    );
    // start with the last block being the current block
    const lastBlock = await this.getCurrentBlock();
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
    let start = end - (this.chainProperties.eventBatchSize - 1);
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
      start = end - (this.chainProperties.eventBatchSize - 1);
      start = Math.max(start, earliestBlockNumber);
    }
  }

  // @dev This function should be implemented for stateful bridges. It should return an array of AssetValue's
  // @dev which define how much a given interaction is worth in terms of Aztec asset ids.
  // @param bigint interactionNonce the interaction nonce to return the value for

  async getInteractionPresentValue(interactionNonce: bigint, inputValue: bigint): Promise<AssetValue[]> {
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
    const accruedInterest = (totalInterest * elapsedTime) / totalTime;
    const totalPresentValue = defiEvent.totalInputValue + accruedInterest;
    const userPresentValue = (totalPresentValue * inputValue) / defiEvent.totalInputValue;

    return [
      {
        assetId: BigInt(BridgeCallData.fromBigInt(defiEvent.encodedBridgeCallData).inputAssetIdA),
        amount: userPresentValue,
      },
    ];
  }

  async getInteractionAPR(interactionNonce: bigint): Promise<number[]> {
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

    const YEAR = 60n * 60n * 24n * 365n;

    const totalInterest = endValue.toBigInt() - defiEvent.totalInputValue;
    const totalTime = exitTimestamp.toBigInt() - BigInt(defiEvent.timestamp);
    const interestPerSecondScaled = divide(totalInterest, totalTime, this.scalingFactor);
    const yearlyInterest = (interestPerSecondScaled * YEAR) / this.scalingFactor;

    const percentageScaled = divide(yearlyInterest, defiEvent.totalInputValue, this.scalingFactor);
    const percentage2sf = (percentageScaled * 10000n) / this.scalingFactor;
    return [Number(percentage2sf) / 100];
  }

  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<bigint[]> {
    const assetExpiries = await this.elementBridgeContract.getAssetExpiries(inputAssetA.erc20Address.toString());
    if (assetExpiries && assetExpiries.length) {
      return assetExpiries.map(a => a.toBigInt());
    }
    return [];
  }

  public auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: "Unix Timestamp of the tranch expiry",
    },
  ];

  async getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    inputValue: bigint,
  ): Promise<bigint[]> {
    // bridge is async the third parameter represents this
    return [BigInt(0), BigInt(0), BigInt(1)];
  }

  async getAPR(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    inputValue: bigint,
  ): Promise<number[]> {
    const assetExpiryHash = await this.elementBridgeContract.hashAssetAndExpiry(
      inputAssetA.erc20Address.toString(),
      auxData,
    );
    const pool = await this.elementBridgeContract.pools(assetExpiryHash);
    const poolId = pool.poolId;
    const trancheAddress = pool.trancheAddress;

    const funds: FundManagement = {
      sender: EthAddress.ZERO.toString(),
      recipient: EthAddress.ZERO.toString(),
      fromInternalBalance: false,
      toInternalBalance: false,
    };

    const step: BatchSwapStep = {
      poolId,
      assetInIndex: 0,
      assetOutIndex: 1,
      amount: inputValue.toString(),
      userData: "0x",
    };

    const deltas = await this.balancerContract.queryBatchSwap(
      SwapType.SwapExactIn,
      [step],
      [inputAssetA.erc20Address.toString(), trancheAddress],
      funds,
    );

    const latestBlock = await this.getCurrentBlock();

    const outputAssetAValue = deltas[1];

    const timeToExpiration = auxData - BigInt(latestBlock.timestamp);

    const YEAR = 60n * 60n * 24n * 365n;
    const interest = -outputAssetAValue.toBigInt() - inputValue;
    const scaledOutput = divide(interest, timeToExpiration, this.scalingFactor);
    const yearlyOutput = (scaledOutput * YEAR) / this.scalingFactor;
    const percentageScaled = divide(yearlyOutput, inputValue, this.scalingFactor);
    const percentage2sf = (percentageScaled * 10000n) / this.scalingFactor;

    return [Number(percentage2sf) / 100];
  }

  async getMarketSize(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
  ): Promise<AssetValue[]> {
    const assetExpiryHash = await this.elementBridgeContract.hashAssetAndExpiry(
      inputAssetA.erc20Address.toString(),
      auxData,
    );
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

  async hasFinalised(interactionNonce: bigint): Promise<boolean> {
    const interaction = await this.elementBridgeContract.interactions(interactionNonce);
    return interaction.finalised;
  }
}
