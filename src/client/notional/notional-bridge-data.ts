import { AssetValue, AuxDataConfig, AztecAsset, BridgeDataFieldGetters, SolidityType } from "../bridge-data";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { createWeb3Provider } from "../aztec/provider";
import { EthAddress } from "@aztec/barretenberg/address";
import { Web3Provider } from "@ethersproject/providers";
import {
  NotionalViews,
  NotionalViews__factory,
  NotionalBridgeContract,
  NotionalBridgeContract__factory,
  IWrappedfCash__factory,
} from "../../../typechain-types";
export class NotionalBridgeData implements BridgeDataFieldGetters {
  currencyId: Map<string, number>;
  toUnderlyingToken: Map<string,string>;
  private constructor(
    private provider: Web3Provider,
    private notionalViewContract: NotionalViews,
    private notionalBridgeContract: NotionalBridgeContract,
  ) {
    this.currencyId = new Map<string, number>();
    this.toUnderlyingToken = new Map<string,string>();
  }

  static async create(provider: EthereumProvider, notionalViewAddress: EthAddress, notionalBridgeAddress: EthAddress) {
    const ethersProvider = createWeb3Provider(provider);
    const notionalViewContract: NotionalViews = NotionalViews__factory.connect(notionalViewAddress.toString(), ethersProvider);
    const notionalBridgeContract = NotionalBridgeContract__factory.connect(
      notionalBridgeAddress.toString(),
      ethersProvider,
    );
    const maxCurrencyId = await notionalViewContract.getMaxCurrencyId();
    let notional = new NotionalBridgeData(ethersProvider, notionalViewContract, notionalBridgeContract);
    for (let i = 1; i <= maxCurrencyId; i++) {
      const [assetToken, underlyingToken] = await notionalViewContract.getCurrency(i);
      notional.currencyId.set(assetToken.tokenAddress, i);
      notional.currencyId.set(underlyingToken.tokenAddress, i);
      notional.toUnderlyingToken.set(assetToken.tokenAddress, underlyingToken.tokenAddress)
      notional.toUnderlyingToken.set(underlyingToken.tokenAddress, underlyingToken.tokenAddress);
    }

    return
  }

  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<bigint[]> {

    const currencyId = this.currencyId.get(inputAssetA.erc20Address.toString());
    if (typeof currencyId !== "undefined") {
      const activeMarkets = await this.notionalViewContract.getActiveMarkets(currencyId);
      return [activeMarkets[0].maturity.toBigInt()];
    }
    return [];
  }

  public auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: "the timestamp of the market maturity we want to enter",
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
    if (auxData === 0n) {
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
      const cashAmount = await this.notionalBridgeContract.computeUnderlyingAmount(
        inputAssetA.erc20Address.toString(),
        this.toUnderlyingToken.get(inputAssetA.erc20Address.toString())!,
        inputValue
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
    auxData: bigint,
  ): Promise<AssetValue[]> {
    let underlyingToken = inputAssetA.erc20Address.toString();
    if (auxData == 0n) {
      // redeem
      const wrappedFcash = IWrappedfCash__factory.connect(inputAssetA.erc20Address.toString(), this.provider);
      underlyingToken = (await wrappedFcash.getUnderlyingToken())._underlyingToken;
    }
    const currencyId = this.currencyId.get(inputAssetA.erc20Address.toString());
    if (typeof currencyId !== "undefined") {
      const market = await this.notionalViewContract.getActiveMarkets(currencyId)[0];
      if (auxData == 0n) {
        return [{ assetId: inputAssetA.id, amount: market.totalAssetCash.toBigInt() }];
      }
      return [{ assetId: inputAssetA.id, amount: market.totalfCash.toBigInt() }];
    }
    throw "Invalid Currency";
  }
}
