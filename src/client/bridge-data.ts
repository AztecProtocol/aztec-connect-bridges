import { EthAddress } from "@aztec/barretenberg/address";

// @dev Parameter assetId is an index of the corresponding address in the array returned from
//      RollupProcessor.getSupportedAssets() incremented by 1 (the increment is there because ETH has id 0 and it is
//      not present in the array)
export interface AssetValue {
  assetId: bigint;
  amount: bigint;
}

export enum AztecAssetType {
  ETH,
  ERC20,
  VIRTUAL,
  NOT_USED,
}

export enum SolidityType {
  uint8,
  uint16,
  uint24,
  uint32,
  uint64,
  boolean,
  string,
  bytes,
}

export interface AztecAsset {
  id: bigint;
  assetType: AztecAssetType;
  erc20Address: EthAddress;
}

export interface AuxDataConfig {
  start: number;
  length: number;
  description: string;
  solidityType: SolidityType;
}

export interface BridgeDataFieldGetters {
  /*
  @dev This function should be implemented for stateful bridges.
  @return The value of the user's share of a given interaction.
  */
  getInteractionPresentValue?(interactionNonce: bigint, inputValue: bigint): Promise<AssetValue[]>;

  /*
  @dev This function should be implemented for all bridges that use auxData which require on-chain data.
  @return The set of possible auxData values that they can use for a given set of input and output assets.
  */
  getAuxData?(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<bigint[]>;

  /*
  @dev This public variable defines the structure of the auxData.
  */
  auxDataConfig: AuxDataConfig[];

  /*
  @dev This function should be implemented for all bridges.
  @return The expected return amounts of outputAssetA and outputAssetB.
  */

  getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    inputValue: bigint,
  ): Promise<bigint[]>;

  /*
  @dev This function should be implemented for async bridges.
  @return The date at which the bridge is expected to be finalised. For limit orders this should be the expiration.
  */
  getExpiration?(interactionNonce: bigint): Promise<bigint>;

  hasFinalised?(interactionNonce: bigint): Promise<boolean>;

  /*
  @dev This function should be implemented for all bridges that are stateful. 
  @return The expected value 1 year from now of outputAssetA and outputAssetB.
  */

  getExpectedYield?(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    inputValue: bigint,
  ): Promise<number[]>;

  /*
  @dev This function should be implemented for all bridges dealing with L1 liquidity.
  @return L1 liquidity this bridge call will be interacting with (e.g the liquidity of the underlying yield pool or AMM
          for a given pair).
  */
  getMarketSize?(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
  ): Promise<AssetValue[]>;

  /*
  @dev This function should be implemented for all async yield bridges.
  @return Yield for a given interaction.
  */
  getCurrentYield?(interactionNonce: bigint): Promise<number[]>;

  /*
  @dev This function should be implemented for swap / LP bridges.
  @return Packed aux data taking into account a dynamic price and fee.
  */
  lPAuxData?(data: bigint[]): Promise<bigint[]>;
}
