export interface AssetValue {
  assetId: bigint; // the Aztec AssetId (this can be queried from the rollup contract)
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
  erc20Address: string;
}

export interface AuxDataConfig {
  start: number;
  length: number;
  description: string;
  solidityType: SolidityType;
}

export interface BridgeDataFieldGetters {
  /*
  @dev This function should be implemented for stateful bridges. It's purpose is to tell the developer using the bridge
  @dev the value of the user's share of a given interaction. The value should be returned as an array of `AssetValue`s.
  */
  getInteractionPresentValue?(interactionNonce: bigint, inputValue: bigint): Promise<AssetValue[]>;

  /*
  @dev This function should be implemented for all bridges that use auxData that require onchain data. It's purpose is to tell the developer using the bridge
  @dev the set of possible auxData's that they can use for a given set of inputOutputAssets.
  */
  getAuxData?(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<bigint[]>;

  /*
  @dev This public variable defines the structure of the auxData
  */
  auxDataConfig: AuxDataConfig[];

  /*
  @dev This function should be implemented for all bridges. It should return the expected value in of the bridgeId given an inputValue
  @dev given inputValue of inputAssetA and inputAssetB
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
  @dev This function should be implemented for async bridges. It should return the date at which the bridge is expected to be finalised.
  @dev For limit orders this should be the expiration.
  */
  getExpiration?(interactionNonce: bigint): Promise<bigint>;

  hasFinalised?(interactionNonce: bigint): Promise<boolean>;

  /*
  @dev This function should be implemented for all bridges are stateful. It should return the expected value 1 year from now of outputAssetA and outputAssetB
  @dev given inputValue of inputAssetA and inputAssetB
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
  @dev This function should be implemented for all bridges dealing with L1 liqudity pools. It should return the Layer liquidity this bridge call will be interacting with
  @dev e.g the liquidity of the underlying yield pool or AMM for a given pair
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
  @dev It should return the yield for a given interaction
  */
  getCurrentYield?(interactionNonce: bigint): Promise<number[]>;

  /*
  @dev This function should be implemented for swap / LP bridges.
  @dev It should return a packed aux data taking into account a dynamic price and fee
  */
  lPAuxData?(data: bigint[]): Promise<bigint[]>;
}
