import { AuxDataConfig, AztecAsset, BridgeDataFieldGetters, SolidityType } from "../bridge-data";
import { AssetValue } from "@aztec/barretenberg/asset";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { createWeb3Provider } from "../aztec/provider";
import { EthAddress } from "@aztec/barretenberg/address";
import { Web3Provider } from "@ethersproject/providers";
import {
  NotionalViews,
  NotionalViews__factory,
  IWrappedfCash__factory,
  CToken__factory,
} from "../../../typechain-types";
import { BigNumber } from "@ethersproject/bignumber";
export class NotionalBridgeData implements BridgeDataFieldGetters {
  currencyId: Map<string, number>;
  toUnderlyingToken: Map<string, string>;
  provider: Web3Provider;
  notionalViewContract: NotionalViews;
  decimals: Map<string, number>;
  private constructor(_provider: Web3Provider, _notionalViewContract: NotionalViews) {
    this.currencyId = new Map<string, number>();
    this.toUnderlyingToken = new Map<string, string>();
    this.provider = _provider;
    this.notionalViewContract = _notionalViewContract;
    this.decimals = new Map<string, number>();
  }

  static async create(provider: EthereumProvider, notionalViewAddress: EthAddress) {
    const ethersProvider = createWeb3Provider(provider);
    const notionalViewContract: NotionalViews = NotionalViews__factory.connect(
      notionalViewAddress.toString(),
      ethersProvider,
    );
    const maxCurrencyId = await notionalViewContract.getMaxCurrencyId();
    const notional = new NotionalBridgeData(ethersProvider, notionalViewContract);
    for (let i = 1; i <= maxCurrencyId; i++) {
      const [assetToken, underlyingToken] = await notionalViewContract.getCurrency(i);
      notional.currencyId.set(assetToken.tokenAddress, i);
      notional.currencyId.set(underlyingToken.tokenAddress, i);
      notional.toUnderlyingToken.set(assetToken.tokenAddress, underlyingToken.tokenAddress);
      notional.toUnderlyingToken.set(underlyingToken.tokenAddress, underlyingToken.tokenAddress);
      notional.decimals.set(underlyingToken.tokenAddress, underlyingToken.decimals.toNumber());
      notional.decimals.set(assetToken.tokenAddress, assetToken.decimals.toNumber());
    }
    return notional;
  }

  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<number[]> {
    const currencyId = this.currencyId.get(inputAssetA.erc20Address.toString());
    if (typeof currencyId !== "undefined") {
      return [1];
    }
    return [0];
  }

  public auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: "Indicates whether this is for entering the market or exiting the market",
    },
  ];

  async getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: number,
    inputValue: bigint,
  ): Promise<bigint[]> {
    if (auxData === 0) {
      const wrappedFcash = IWrappedfCash__factory.connect(inputAssetA.erc20Address.toString(), this.provider);
      const underlyingToken = (await wrappedFcash.getUnderlyingToken())._underlyingToken;
      const currencyId = await this.notionalViewContract.getCurrencyId(underlyingToken);
      const [assetAmount, underlyingAmount] = await this.notionalViewContract.getCashAmountGivenfCashAmount(
        currencyId,
        inputValue,
        0,
        Date.now(),
      );
      if (outputAssetA.erc20Address.toString() === underlyingToken) {
        return [underlyingAmount.toBigInt()];
      }
      return [assetAmount.toBigInt()];
    }
    const currencyId = this.currencyId.get(inputAssetA.erc20Address.toString());
    if (typeof currencyId !== "undefined") {
      const cashAmount = await this.computeUnderlyingAmount(
        this.toUnderlyingToken.get(inputAssetA.erc20Address.toString())!,
        inputAssetA.erc20Address.toString(),
        BigNumber.from(inputValue),
      );
      const fcashAmount = await this.notionalViewContract.getfCashAmountGivenCashAmount(
        currencyId,
        -cashAmount,
        0,
        Date.now(),
      );
      return [fcashAmount.toBigInt()];
    }
    throw "Invalid Currency";
  }

  async getMarketSize(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: number,
  ): Promise<AssetValue[]> {
    let underlyingToken = inputAssetA.erc20Address.toString();
    if (auxData === 0) {
      // redeem
      const wrappedFcash = IWrappedfCash__factory.connect(inputAssetA.erc20Address.toString(), this.provider);
      underlyingToken = (await wrappedFcash.getUnderlyingToken())._underlyingToken;
    }
    const currencyId = this.currencyId.get(inputAssetA.erc20Address.toString());
    if (typeof currencyId !== "undefined") {
      const market = (await this.notionalViewContract.getActiveMarkets(currencyId))[0];
      if (auxData === 0) {
        return [{ assetId: inputAssetA.id, value: market.totalAssetCash.toBigInt() }];
      }
      return [{ assetId: inputAssetA.id, value: market.totalfCash.toBigInt() }];
    }
    throw "Invalid Currency";
  }

  async computeUnderlyingAmount(underlyingToken: string, token: string, amount: BigNumber) {
    const underlyingDecimals =
      EthAddress.fromString(underlyingToken) != EthAddress.ZERO ? this.decimals.get(underlyingToken)! : 18;
    if (token != underlyingToken) {
      // if token is not underlying token, token should be a cToken
      const tokenContract = CToken__factory.connect(token, this.provider);
      const exchangeRateCurrent = await tokenContract.exchangeRateCurrent();
      const mantissa = 10 + underlyingDecimals;
      const underlyingAmount = amount.mul(BigNumber.from(exchangeRateCurrent)).div(10 ** mantissa);
      return underlyingAmount;
    }
    if (underlyingDecimals >= 8) {
      return amount.div(10 ** (underlyingDecimals - 8));
    }
    return amount.mul(10 ** (8 - underlyingDecimals));
  }
}
