/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import type {
  BaseContract,
  BigNumber,
  BigNumberish,
  BytesLike,
  CallOverrides,
  ContractTransaction,
  Overrides,
  PayableOverrides,
  PopulatedTransaction,
  Signer,
  utils,
} from "ethers";
import type {
  FunctionFragment,
  Result,
  EventFragment,
} from "@ethersproject/abi";
import type { Listener, Provider } from "@ethersproject/providers";
import type {
  TypedEventFilter,
  TypedEvent,
  TypedListener,
  OnEvent,
  PromiseOrValue,
} from "./common.js";

export declare namespace AztecTypes {
  export type AztecAssetStruct = {
    id: PromiseOrValue<BigNumberish>;
    erc20Address: PromiseOrValue<string>;
    assetType: PromiseOrValue<BigNumberish>;
  };

  export type AztecAssetStructOutput = [BigNumber, string, number] & {
    id: BigNumber;
    erc20Address: string;
    assetType: number;
  };
}

export interface TroveBridgeInterface extends utils.Interface {
  functions: {
    "BORROWER_OPERATIONS()": FunctionFragment;
    "DUST()": FunctionFragment;
    "INITIAL_ICR()": FunctionFragment;
    "LUSD()": FunctionFragment;
    "LUSD_USDC_POOL()": FunctionFragment;
    "PRECISION()": FunctionFragment;
    "ROLLUP_PROCESSOR()": FunctionFragment;
    "SORTED_TROVES()": FunctionFragment;
    "SUBSIDY()": FunctionFragment;
    "TROVE_MANAGER()": FunctionFragment;
    "USDC()": FunctionFragment;
    "USDC_ETH_POOL()": FunctionFragment;
    "WETH()": FunctionFragment;
    "allowance(address,address)": FunctionFragment;
    "approve(address,uint256)": FunctionFragment;
    "balanceOf(address)": FunctionFragment;
    "closeTrove()": FunctionFragment;
    "computeAmtToBorrow(uint256)": FunctionFragment;
    "computeCriteria((uint256,address,uint8),(uint256,address,uint8),(uint256,address,uint8),(uint256,address,uint8),uint64)": FunctionFragment;
    "convert((uint256,address,uint8),(uint256,address,uint8),(uint256,address,uint8),(uint256,address,uint8),uint256,uint256,uint64,address)": FunctionFragment;
    "decimals()": FunctionFragment;
    "decreaseAllowance(address,uint256)": FunctionFragment;
    "finalise((uint256,address,uint8),(uint256,address,uint8),(uint256,address,uint8),(uint256,address,uint8),uint256,uint64)": FunctionFragment;
    "increaseAllowance(address,uint256)": FunctionFragment;
    "name()": FunctionFragment;
    "openTrove(address,address,uint256)": FunctionFragment;
    "owner()": FunctionFragment;
    "renounceOwnership()": FunctionFragment;
    "symbol()": FunctionFragment;
    "totalSupply()": FunctionFragment;
    "transfer(address,uint256)": FunctionFragment;
    "transferFrom(address,address,uint256)": FunctionFragment;
    "transferOwnership(address)": FunctionFragment;
    "uniswapV3SwapCallback(int256,int256,bytes)": FunctionFragment;
  };

  getFunction(
    nameOrSignatureOrTopic:
      | "BORROWER_OPERATIONS"
      | "DUST"
      | "INITIAL_ICR"
      | "LUSD"
      | "LUSD_USDC_POOL"
      | "PRECISION"
      | "ROLLUP_PROCESSOR"
      | "SORTED_TROVES"
      | "SUBSIDY"
      | "TROVE_MANAGER"
      | "USDC"
      | "USDC_ETH_POOL"
      | "WETH"
      | "allowance"
      | "approve"
      | "balanceOf"
      | "closeTrove"
      | "computeAmtToBorrow"
      | "computeCriteria"
      | "convert"
      | "decimals"
      | "decreaseAllowance"
      | "finalise"
      | "increaseAllowance"
      | "name"
      | "openTrove"
      | "owner"
      | "renounceOwnership"
      | "symbol"
      | "totalSupply"
      | "transfer"
      | "transferFrom"
      | "transferOwnership"
      | "uniswapV3SwapCallback"
  ): FunctionFragment;

  encodeFunctionData(
    functionFragment: "BORROWER_OPERATIONS",
    values?: undefined
  ): string;
  encodeFunctionData(functionFragment: "DUST", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "INITIAL_ICR",
    values?: undefined
  ): string;
  encodeFunctionData(functionFragment: "LUSD", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "LUSD_USDC_POOL",
    values?: undefined
  ): string;
  encodeFunctionData(functionFragment: "PRECISION", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "ROLLUP_PROCESSOR",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "SORTED_TROVES",
    values?: undefined
  ): string;
  encodeFunctionData(functionFragment: "SUBSIDY", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "TROVE_MANAGER",
    values?: undefined
  ): string;
  encodeFunctionData(functionFragment: "USDC", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "USDC_ETH_POOL",
    values?: undefined
  ): string;
  encodeFunctionData(functionFragment: "WETH", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "allowance",
    values: [PromiseOrValue<string>, PromiseOrValue<string>]
  ): string;
  encodeFunctionData(
    functionFragment: "approve",
    values: [PromiseOrValue<string>, PromiseOrValue<BigNumberish>]
  ): string;
  encodeFunctionData(
    functionFragment: "balanceOf",
    values: [PromiseOrValue<string>]
  ): string;
  encodeFunctionData(
    functionFragment: "closeTrove",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "computeAmtToBorrow",
    values: [PromiseOrValue<BigNumberish>]
  ): string;
  encodeFunctionData(
    functionFragment: "computeCriteria",
    values: [
      AztecTypes.AztecAssetStruct,
      AztecTypes.AztecAssetStruct,
      AztecTypes.AztecAssetStruct,
      AztecTypes.AztecAssetStruct,
      PromiseOrValue<BigNumberish>
    ]
  ): string;
  encodeFunctionData(
    functionFragment: "convert",
    values: [
      AztecTypes.AztecAssetStruct,
      AztecTypes.AztecAssetStruct,
      AztecTypes.AztecAssetStruct,
      AztecTypes.AztecAssetStruct,
      PromiseOrValue<BigNumberish>,
      PromiseOrValue<BigNumberish>,
      PromiseOrValue<BigNumberish>,
      PromiseOrValue<string>
    ]
  ): string;
  encodeFunctionData(functionFragment: "decimals", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "decreaseAllowance",
    values: [PromiseOrValue<string>, PromiseOrValue<BigNumberish>]
  ): string;
  encodeFunctionData(
    functionFragment: "finalise",
    values: [
      AztecTypes.AztecAssetStruct,
      AztecTypes.AztecAssetStruct,
      AztecTypes.AztecAssetStruct,
      AztecTypes.AztecAssetStruct,
      PromiseOrValue<BigNumberish>,
      PromiseOrValue<BigNumberish>
    ]
  ): string;
  encodeFunctionData(
    functionFragment: "increaseAllowance",
    values: [PromiseOrValue<string>, PromiseOrValue<BigNumberish>]
  ): string;
  encodeFunctionData(functionFragment: "name", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "openTrove",
    values: [
      PromiseOrValue<string>,
      PromiseOrValue<string>,
      PromiseOrValue<BigNumberish>
    ]
  ): string;
  encodeFunctionData(functionFragment: "owner", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "renounceOwnership",
    values?: undefined
  ): string;
  encodeFunctionData(functionFragment: "symbol", values?: undefined): string;
  encodeFunctionData(
    functionFragment: "totalSupply",
    values?: undefined
  ): string;
  encodeFunctionData(
    functionFragment: "transfer",
    values: [PromiseOrValue<string>, PromiseOrValue<BigNumberish>]
  ): string;
  encodeFunctionData(
    functionFragment: "transferFrom",
    values: [
      PromiseOrValue<string>,
      PromiseOrValue<string>,
      PromiseOrValue<BigNumberish>
    ]
  ): string;
  encodeFunctionData(
    functionFragment: "transferOwnership",
    values: [PromiseOrValue<string>]
  ): string;
  encodeFunctionData(
    functionFragment: "uniswapV3SwapCallback",
    values: [
      PromiseOrValue<BigNumberish>,
      PromiseOrValue<BigNumberish>,
      PromiseOrValue<BytesLike>
    ]
  ): string;

  decodeFunctionResult(
    functionFragment: "BORROWER_OPERATIONS",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "DUST", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "INITIAL_ICR",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "LUSD", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "LUSD_USDC_POOL",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "PRECISION", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "ROLLUP_PROCESSOR",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "SORTED_TROVES",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "SUBSIDY", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "TROVE_MANAGER",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "USDC", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "USDC_ETH_POOL",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "WETH", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "allowance", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "approve", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "balanceOf", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "closeTrove", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "computeAmtToBorrow",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "computeCriteria",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "convert", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "decimals", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "decreaseAllowance",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "finalise", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "increaseAllowance",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "name", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "openTrove", data: BytesLike): Result;
  decodeFunctionResult(functionFragment: "owner", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "renounceOwnership",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "symbol", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "totalSupply",
    data: BytesLike
  ): Result;
  decodeFunctionResult(functionFragment: "transfer", data: BytesLike): Result;
  decodeFunctionResult(
    functionFragment: "transferFrom",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "transferOwnership",
    data: BytesLike
  ): Result;
  decodeFunctionResult(
    functionFragment: "uniswapV3SwapCallback",
    data: BytesLike
  ): Result;

  events: {
    "Approval(address,address,uint256)": EventFragment;
    "OwnershipTransferred(address,address)": EventFragment;
    "Transfer(address,address,uint256)": EventFragment;
  };

  getEvent(nameOrSignatureOrTopic: "Approval"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "OwnershipTransferred"): EventFragment;
  getEvent(nameOrSignatureOrTopic: "Transfer"): EventFragment;
}

export interface ApprovalEventObject {
  owner: string;
  spender: string;
  value: BigNumber;
}
export type ApprovalEvent = TypedEvent<
  [string, string, BigNumber],
  ApprovalEventObject
>;

export type ApprovalEventFilter = TypedEventFilter<ApprovalEvent>;

export interface OwnershipTransferredEventObject {
  previousOwner: string;
  newOwner: string;
}
export type OwnershipTransferredEvent = TypedEvent<
  [string, string],
  OwnershipTransferredEventObject
>;

export type OwnershipTransferredEventFilter =
  TypedEventFilter<OwnershipTransferredEvent>;

export interface TransferEventObject {
  from: string;
  to: string;
  value: BigNumber;
}
export type TransferEvent = TypedEvent<
  [string, string, BigNumber],
  TransferEventObject
>;

export type TransferEventFilter = TypedEventFilter<TransferEvent>;

export interface TroveBridge extends BaseContract {
  connect(signerOrProvider: Signer | Provider | string): this;
  attach(addressOrName: string): this;
  deployed(): Promise<this>;

  interface: TroveBridgeInterface;

  queryFilter<TEvent extends TypedEvent>(
    event: TypedEventFilter<TEvent>,
    fromBlockOrBlockhash?: string | number | undefined,
    toBlock?: string | number | undefined
  ): Promise<Array<TEvent>>;

  listeners<TEvent extends TypedEvent>(
    eventFilter?: TypedEventFilter<TEvent>
  ): Array<TypedListener<TEvent>>;
  listeners(eventName?: string): Array<Listener>;
  removeAllListeners<TEvent extends TypedEvent>(
    eventFilter: TypedEventFilter<TEvent>
  ): this;
  removeAllListeners(eventName?: string): this;
  off: OnEvent<this>;
  on: OnEvent<this>;
  once: OnEvent<this>;
  removeListener: OnEvent<this>;

  functions: {
    BORROWER_OPERATIONS(overrides?: CallOverrides): Promise<[string]>;

    DUST(overrides?: CallOverrides): Promise<[BigNumber]>;

    INITIAL_ICR(overrides?: CallOverrides): Promise<[BigNumber]>;

    LUSD(overrides?: CallOverrides): Promise<[string]>;

    LUSD_USDC_POOL(overrides?: CallOverrides): Promise<[string]>;

    PRECISION(overrides?: CallOverrides): Promise<[BigNumber]>;

    ROLLUP_PROCESSOR(overrides?: CallOverrides): Promise<[string]>;

    SORTED_TROVES(overrides?: CallOverrides): Promise<[string]>;

    SUBSIDY(overrides?: CallOverrides): Promise<[string]>;

    TROVE_MANAGER(overrides?: CallOverrides): Promise<[string]>;

    USDC(overrides?: CallOverrides): Promise<[string]>;

    USDC_ETH_POOL(overrides?: CallOverrides): Promise<[string]>;

    WETH(overrides?: CallOverrides): Promise<[string]>;

    allowance(
      owner: PromiseOrValue<string>,
      spender: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<[BigNumber]>;

    approve(
      spender: PromiseOrValue<string>,
      amount: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    balanceOf(
      account: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<[BigNumber]>;

    closeTrove(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    computeAmtToBorrow(
      _collateral: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    computeCriteria(
      arg0: AztecTypes.AztecAssetStruct,
      arg1: AztecTypes.AztecAssetStruct,
      arg2: AztecTypes.AztecAssetStruct,
      arg3: AztecTypes.AztecAssetStruct,
      arg4: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<[BigNumber]>;

    convert(
      _inputAssetA: AztecTypes.AztecAssetStruct,
      _inputAssetB: AztecTypes.AztecAssetStruct,
      _outputAssetA: AztecTypes.AztecAssetStruct,
      _outputAssetB: AztecTypes.AztecAssetStruct,
      _totalInputValue: PromiseOrValue<BigNumberish>,
      _interactionNonce: PromiseOrValue<BigNumberish>,
      _auxData: PromiseOrValue<BigNumberish>,
      _rollupBeneficiary: PromiseOrValue<string>,
      overrides?: PayableOverrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    decimals(overrides?: CallOverrides): Promise<[number]>;

    decreaseAllowance(
      spender: PromiseOrValue<string>,
      subtractedValue: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    finalise(
      arg0: AztecTypes.AztecAssetStruct,
      arg1: AztecTypes.AztecAssetStruct,
      arg2: AztecTypes.AztecAssetStruct,
      arg3: AztecTypes.AztecAssetStruct,
      arg4: PromiseOrValue<BigNumberish>,
      arg5: PromiseOrValue<BigNumberish>,
      overrides?: PayableOverrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    increaseAllowance(
      spender: PromiseOrValue<string>,
      addedValue: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    name(overrides?: CallOverrides): Promise<[string]>;

    openTrove(
      _upperHint: PromiseOrValue<string>,
      _lowerHint: PromiseOrValue<string>,
      _maxFee: PromiseOrValue<BigNumberish>,
      overrides?: PayableOverrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    owner(overrides?: CallOverrides): Promise<[string]>;

    renounceOwnership(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    symbol(overrides?: CallOverrides): Promise<[string]>;

    totalSupply(overrides?: CallOverrides): Promise<[BigNumber]>;

    transfer(
      to: PromiseOrValue<string>,
      amount: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    transferFrom(
      from: PromiseOrValue<string>,
      to: PromiseOrValue<string>,
      amount: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    transferOwnership(
      newOwner: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;

    uniswapV3SwapCallback(
      _amount0Delta: PromiseOrValue<BigNumberish>,
      _amount1Delta: PromiseOrValue<BigNumberish>,
      _data: PromiseOrValue<BytesLike>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<ContractTransaction>;
  };

  BORROWER_OPERATIONS(overrides?: CallOverrides): Promise<string>;

  DUST(overrides?: CallOverrides): Promise<BigNumber>;

  INITIAL_ICR(overrides?: CallOverrides): Promise<BigNumber>;

  LUSD(overrides?: CallOverrides): Promise<string>;

  LUSD_USDC_POOL(overrides?: CallOverrides): Promise<string>;

  PRECISION(overrides?: CallOverrides): Promise<BigNumber>;

  ROLLUP_PROCESSOR(overrides?: CallOverrides): Promise<string>;

  SORTED_TROVES(overrides?: CallOverrides): Promise<string>;

  SUBSIDY(overrides?: CallOverrides): Promise<string>;

  TROVE_MANAGER(overrides?: CallOverrides): Promise<string>;

  USDC(overrides?: CallOverrides): Promise<string>;

  USDC_ETH_POOL(overrides?: CallOverrides): Promise<string>;

  WETH(overrides?: CallOverrides): Promise<string>;

  allowance(
    owner: PromiseOrValue<string>,
    spender: PromiseOrValue<string>,
    overrides?: CallOverrides
  ): Promise<BigNumber>;

  approve(
    spender: PromiseOrValue<string>,
    amount: PromiseOrValue<BigNumberish>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  balanceOf(
    account: PromiseOrValue<string>,
    overrides?: CallOverrides
  ): Promise<BigNumber>;

  closeTrove(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  computeAmtToBorrow(
    _collateral: PromiseOrValue<BigNumberish>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  computeCriteria(
    arg0: AztecTypes.AztecAssetStruct,
    arg1: AztecTypes.AztecAssetStruct,
    arg2: AztecTypes.AztecAssetStruct,
    arg3: AztecTypes.AztecAssetStruct,
    arg4: PromiseOrValue<BigNumberish>,
    overrides?: CallOverrides
  ): Promise<BigNumber>;

  convert(
    _inputAssetA: AztecTypes.AztecAssetStruct,
    _inputAssetB: AztecTypes.AztecAssetStruct,
    _outputAssetA: AztecTypes.AztecAssetStruct,
    _outputAssetB: AztecTypes.AztecAssetStruct,
    _totalInputValue: PromiseOrValue<BigNumberish>,
    _interactionNonce: PromiseOrValue<BigNumberish>,
    _auxData: PromiseOrValue<BigNumberish>,
    _rollupBeneficiary: PromiseOrValue<string>,
    overrides?: PayableOverrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  decimals(overrides?: CallOverrides): Promise<number>;

  decreaseAllowance(
    spender: PromiseOrValue<string>,
    subtractedValue: PromiseOrValue<BigNumberish>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  finalise(
    arg0: AztecTypes.AztecAssetStruct,
    arg1: AztecTypes.AztecAssetStruct,
    arg2: AztecTypes.AztecAssetStruct,
    arg3: AztecTypes.AztecAssetStruct,
    arg4: PromiseOrValue<BigNumberish>,
    arg5: PromiseOrValue<BigNumberish>,
    overrides?: PayableOverrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  increaseAllowance(
    spender: PromiseOrValue<string>,
    addedValue: PromiseOrValue<BigNumberish>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  name(overrides?: CallOverrides): Promise<string>;

  openTrove(
    _upperHint: PromiseOrValue<string>,
    _lowerHint: PromiseOrValue<string>,
    _maxFee: PromiseOrValue<BigNumberish>,
    overrides?: PayableOverrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  owner(overrides?: CallOverrides): Promise<string>;

  renounceOwnership(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  symbol(overrides?: CallOverrides): Promise<string>;

  totalSupply(overrides?: CallOverrides): Promise<BigNumber>;

  transfer(
    to: PromiseOrValue<string>,
    amount: PromiseOrValue<BigNumberish>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  transferFrom(
    from: PromiseOrValue<string>,
    to: PromiseOrValue<string>,
    amount: PromiseOrValue<BigNumberish>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  transferOwnership(
    newOwner: PromiseOrValue<string>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  uniswapV3SwapCallback(
    _amount0Delta: PromiseOrValue<BigNumberish>,
    _amount1Delta: PromiseOrValue<BigNumberish>,
    _data: PromiseOrValue<BytesLike>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ContractTransaction>;

  callStatic: {
    BORROWER_OPERATIONS(overrides?: CallOverrides): Promise<string>;

    DUST(overrides?: CallOverrides): Promise<BigNumber>;

    INITIAL_ICR(overrides?: CallOverrides): Promise<BigNumber>;

    LUSD(overrides?: CallOverrides): Promise<string>;

    LUSD_USDC_POOL(overrides?: CallOverrides): Promise<string>;

    PRECISION(overrides?: CallOverrides): Promise<BigNumber>;

    ROLLUP_PROCESSOR(overrides?: CallOverrides): Promise<string>;

    SORTED_TROVES(overrides?: CallOverrides): Promise<string>;

    SUBSIDY(overrides?: CallOverrides): Promise<string>;

    TROVE_MANAGER(overrides?: CallOverrides): Promise<string>;

    USDC(overrides?: CallOverrides): Promise<string>;

    USDC_ETH_POOL(overrides?: CallOverrides): Promise<string>;

    WETH(overrides?: CallOverrides): Promise<string>;

    allowance(
      owner: PromiseOrValue<string>,
      spender: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    approve(
      spender: PromiseOrValue<string>,
      amount: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<boolean>;

    balanceOf(
      account: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    closeTrove(overrides?: CallOverrides): Promise<void>;

    computeAmtToBorrow(
      _collateral: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    computeCriteria(
      arg0: AztecTypes.AztecAssetStruct,
      arg1: AztecTypes.AztecAssetStruct,
      arg2: AztecTypes.AztecAssetStruct,
      arg3: AztecTypes.AztecAssetStruct,
      arg4: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    convert(
      _inputAssetA: AztecTypes.AztecAssetStruct,
      _inputAssetB: AztecTypes.AztecAssetStruct,
      _outputAssetA: AztecTypes.AztecAssetStruct,
      _outputAssetB: AztecTypes.AztecAssetStruct,
      _totalInputValue: PromiseOrValue<BigNumberish>,
      _interactionNonce: PromiseOrValue<BigNumberish>,
      _auxData: PromiseOrValue<BigNumberish>,
      _rollupBeneficiary: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<
      [BigNumber, BigNumber, boolean] & {
        outputValueA: BigNumber;
        outputValueB: BigNumber;
      }
    >;

    decimals(overrides?: CallOverrides): Promise<number>;

    decreaseAllowance(
      spender: PromiseOrValue<string>,
      subtractedValue: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<boolean>;

    finalise(
      arg0: AztecTypes.AztecAssetStruct,
      arg1: AztecTypes.AztecAssetStruct,
      arg2: AztecTypes.AztecAssetStruct,
      arg3: AztecTypes.AztecAssetStruct,
      arg4: PromiseOrValue<BigNumberish>,
      arg5: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<[BigNumber, BigNumber, boolean]>;

    increaseAllowance(
      spender: PromiseOrValue<string>,
      addedValue: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<boolean>;

    name(overrides?: CallOverrides): Promise<string>;

    openTrove(
      _upperHint: PromiseOrValue<string>,
      _lowerHint: PromiseOrValue<string>,
      _maxFee: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<void>;

    owner(overrides?: CallOverrides): Promise<string>;

    renounceOwnership(overrides?: CallOverrides): Promise<void>;

    symbol(overrides?: CallOverrides): Promise<string>;

    totalSupply(overrides?: CallOverrides): Promise<BigNumber>;

    transfer(
      to: PromiseOrValue<string>,
      amount: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<boolean>;

    transferFrom(
      from: PromiseOrValue<string>,
      to: PromiseOrValue<string>,
      amount: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<boolean>;

    transferOwnership(
      newOwner: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<void>;

    uniswapV3SwapCallback(
      _amount0Delta: PromiseOrValue<BigNumberish>,
      _amount1Delta: PromiseOrValue<BigNumberish>,
      _data: PromiseOrValue<BytesLike>,
      overrides?: CallOverrides
    ): Promise<void>;
  };

  filters: {
    "Approval(address,address,uint256)"(
      owner?: PromiseOrValue<string> | null,
      spender?: PromiseOrValue<string> | null,
      value?: null
    ): ApprovalEventFilter;
    Approval(
      owner?: PromiseOrValue<string> | null,
      spender?: PromiseOrValue<string> | null,
      value?: null
    ): ApprovalEventFilter;

    "OwnershipTransferred(address,address)"(
      previousOwner?: PromiseOrValue<string> | null,
      newOwner?: PromiseOrValue<string> | null
    ): OwnershipTransferredEventFilter;
    OwnershipTransferred(
      previousOwner?: PromiseOrValue<string> | null,
      newOwner?: PromiseOrValue<string> | null
    ): OwnershipTransferredEventFilter;

    "Transfer(address,address,uint256)"(
      from?: PromiseOrValue<string> | null,
      to?: PromiseOrValue<string> | null,
      value?: null
    ): TransferEventFilter;
    Transfer(
      from?: PromiseOrValue<string> | null,
      to?: PromiseOrValue<string> | null,
      value?: null
    ): TransferEventFilter;
  };

  estimateGas: {
    BORROWER_OPERATIONS(overrides?: CallOverrides): Promise<BigNumber>;

    DUST(overrides?: CallOverrides): Promise<BigNumber>;

    INITIAL_ICR(overrides?: CallOverrides): Promise<BigNumber>;

    LUSD(overrides?: CallOverrides): Promise<BigNumber>;

    LUSD_USDC_POOL(overrides?: CallOverrides): Promise<BigNumber>;

    PRECISION(overrides?: CallOverrides): Promise<BigNumber>;

    ROLLUP_PROCESSOR(overrides?: CallOverrides): Promise<BigNumber>;

    SORTED_TROVES(overrides?: CallOverrides): Promise<BigNumber>;

    SUBSIDY(overrides?: CallOverrides): Promise<BigNumber>;

    TROVE_MANAGER(overrides?: CallOverrides): Promise<BigNumber>;

    USDC(overrides?: CallOverrides): Promise<BigNumber>;

    USDC_ETH_POOL(overrides?: CallOverrides): Promise<BigNumber>;

    WETH(overrides?: CallOverrides): Promise<BigNumber>;

    allowance(
      owner: PromiseOrValue<string>,
      spender: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    approve(
      spender: PromiseOrValue<string>,
      amount: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    balanceOf(
      account: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    closeTrove(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    computeAmtToBorrow(
      _collateral: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    computeCriteria(
      arg0: AztecTypes.AztecAssetStruct,
      arg1: AztecTypes.AztecAssetStruct,
      arg2: AztecTypes.AztecAssetStruct,
      arg3: AztecTypes.AztecAssetStruct,
      arg4: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<BigNumber>;

    convert(
      _inputAssetA: AztecTypes.AztecAssetStruct,
      _inputAssetB: AztecTypes.AztecAssetStruct,
      _outputAssetA: AztecTypes.AztecAssetStruct,
      _outputAssetB: AztecTypes.AztecAssetStruct,
      _totalInputValue: PromiseOrValue<BigNumberish>,
      _interactionNonce: PromiseOrValue<BigNumberish>,
      _auxData: PromiseOrValue<BigNumberish>,
      _rollupBeneficiary: PromiseOrValue<string>,
      overrides?: PayableOverrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    decimals(overrides?: CallOverrides): Promise<BigNumber>;

    decreaseAllowance(
      spender: PromiseOrValue<string>,
      subtractedValue: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    finalise(
      arg0: AztecTypes.AztecAssetStruct,
      arg1: AztecTypes.AztecAssetStruct,
      arg2: AztecTypes.AztecAssetStruct,
      arg3: AztecTypes.AztecAssetStruct,
      arg4: PromiseOrValue<BigNumberish>,
      arg5: PromiseOrValue<BigNumberish>,
      overrides?: PayableOverrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    increaseAllowance(
      spender: PromiseOrValue<string>,
      addedValue: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    name(overrides?: CallOverrides): Promise<BigNumber>;

    openTrove(
      _upperHint: PromiseOrValue<string>,
      _lowerHint: PromiseOrValue<string>,
      _maxFee: PromiseOrValue<BigNumberish>,
      overrides?: PayableOverrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    owner(overrides?: CallOverrides): Promise<BigNumber>;

    renounceOwnership(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    symbol(overrides?: CallOverrides): Promise<BigNumber>;

    totalSupply(overrides?: CallOverrides): Promise<BigNumber>;

    transfer(
      to: PromiseOrValue<string>,
      amount: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    transferFrom(
      from: PromiseOrValue<string>,
      to: PromiseOrValue<string>,
      amount: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    transferOwnership(
      newOwner: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;

    uniswapV3SwapCallback(
      _amount0Delta: PromiseOrValue<BigNumberish>,
      _amount1Delta: PromiseOrValue<BigNumberish>,
      _data: PromiseOrValue<BytesLike>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<BigNumber>;
  };

  populateTransaction: {
    BORROWER_OPERATIONS(
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    DUST(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    INITIAL_ICR(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    LUSD(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    LUSD_USDC_POOL(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    PRECISION(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    ROLLUP_PROCESSOR(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    SORTED_TROVES(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    SUBSIDY(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    TROVE_MANAGER(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    USDC(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    USDC_ETH_POOL(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    WETH(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    allowance(
      owner: PromiseOrValue<string>,
      spender: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    approve(
      spender: PromiseOrValue<string>,
      amount: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    balanceOf(
      account: PromiseOrValue<string>,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    closeTrove(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    computeAmtToBorrow(
      _collateral: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    computeCriteria(
      arg0: AztecTypes.AztecAssetStruct,
      arg1: AztecTypes.AztecAssetStruct,
      arg2: AztecTypes.AztecAssetStruct,
      arg3: AztecTypes.AztecAssetStruct,
      arg4: PromiseOrValue<BigNumberish>,
      overrides?: CallOverrides
    ): Promise<PopulatedTransaction>;

    convert(
      _inputAssetA: AztecTypes.AztecAssetStruct,
      _inputAssetB: AztecTypes.AztecAssetStruct,
      _outputAssetA: AztecTypes.AztecAssetStruct,
      _outputAssetB: AztecTypes.AztecAssetStruct,
      _totalInputValue: PromiseOrValue<BigNumberish>,
      _interactionNonce: PromiseOrValue<BigNumberish>,
      _auxData: PromiseOrValue<BigNumberish>,
      _rollupBeneficiary: PromiseOrValue<string>,
      overrides?: PayableOverrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    decimals(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    decreaseAllowance(
      spender: PromiseOrValue<string>,
      subtractedValue: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    finalise(
      arg0: AztecTypes.AztecAssetStruct,
      arg1: AztecTypes.AztecAssetStruct,
      arg2: AztecTypes.AztecAssetStruct,
      arg3: AztecTypes.AztecAssetStruct,
      arg4: PromiseOrValue<BigNumberish>,
      arg5: PromiseOrValue<BigNumberish>,
      overrides?: PayableOverrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    increaseAllowance(
      spender: PromiseOrValue<string>,
      addedValue: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    name(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    openTrove(
      _upperHint: PromiseOrValue<string>,
      _lowerHint: PromiseOrValue<string>,
      _maxFee: PromiseOrValue<BigNumberish>,
      overrides?: PayableOverrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    owner(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    renounceOwnership(
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    symbol(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    totalSupply(overrides?: CallOverrides): Promise<PopulatedTransaction>;

    transfer(
      to: PromiseOrValue<string>,
      amount: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    transferFrom(
      from: PromiseOrValue<string>,
      to: PromiseOrValue<string>,
      amount: PromiseOrValue<BigNumberish>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    transferOwnership(
      newOwner: PromiseOrValue<string>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;

    uniswapV3SwapCallback(
      _amount0Delta: PromiseOrValue<BigNumberish>,
      _amount1Delta: PromiseOrValue<BigNumberish>,
      _data: PromiseOrValue<BytesLike>,
      overrides?: Overrides & { from?: PromiseOrValue<string> }
    ): Promise<PopulatedTransaction>;
  };
}
