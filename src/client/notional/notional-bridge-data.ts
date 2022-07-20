import { AssetValue, AuxDataConfig, AztecAsset, BridgeDataFieldGetters, SolidityType } from "../bridge-data";
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { createWeb3Provider } from "../aztec/provider";
import { EthAddress } from "@aztec/barretenberg/address";
import { NotionalViews, 
  NotionalViews__factory, 
  NotionalBridgeContract, 
  NotionalBridgeContract__factory, 
  IWrappedfCash__factory
} from "../../../typechain-types";
import { Web3Provider } from "@ethersproject/providers";
export class NotionalBridgeData implements BridgeDataFieldGetters {
  private constructor(private provider: Web3Provider,private notionalViewContract: NotionalViews, private notionalBridgeContract: NotionalBridgeContract) {
  }

  static create(
    provider: EthereumProvider,
    notionalViewAddress: EthAddress,
    notionalBridgeAddress: EthAddress
  ) {
    const ethersProvider = createWeb3Provider(provider);
    const notionalViewContract = NotionalViews__factory.connect(notionalViewAddress.toString(), ethersProvider);
    const notionalBridgeContract = NotionalBridgeContract__factory.connect(notionalBridgeAddress.toString(), ethersProvider);
    return new NotionalBridgeData(ethersProvider,notionalViewContract, notionalBridgeContract);
=======
import Notional from "@notional-finance/sdk-v2";
import { Provider } from "@ethersproject/providers";
import { TypedBigNumber, BigNumberType } from "@notional-finance/sdk-v2";

export class NotionalBridgeData implements BridgeDataFieldGetters {
  notional: Notional;
  provider: Provider;
  currencyId: Map<string, number>;
  addressSymbol: Map<string, string>;
  cToken: Set<string>;
=======
=======
>>>>>>> 6be78da2 (add notional bridge)
import Notional from "@notional-finance/sdk-v2";
import { Provider } from "@ethersproject/providers";
import { TypedBigNumber, BigNumberType } from "@notional-finance/sdk-v2"

export class NotionalBridgeData implements BridgeDataFieldGetters {
  notional: Notional
  provider: Provider
  currencyId: Map<string, number>
  addressSymbol: Map<string, string>
  cToken: Set<string>
<<<<<<< HEAD
>>>>>>> 70661815 (add notional bridge)
=======
>>>>>>> 6be78da2 (add notional bridge)
  ETH = "0x0000000000000000000000000000000000000000";
  CETH = "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5";
  DAI = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
  CDAI = "0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643";
  WETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";
  USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
  CUSDC = "0x39AA39c021dfbaE8faC545936693aC917d5E7563";
  WBTC = "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599";
  CWBTC = "0xC11b1268C1A384e55C48c2391d8d480264A3A7F4";
  constructor(_provider: Provider) {
    this.provider = _provider;
    this.currencyId = new Map<string, number>();
    this.currencyId.set(this.ETH, 1);
    this.currencyId.set(this.CETH, 1);
    this.currencyId.set(this.WETH, 1);
    this.currencyId.set(this.DAI, 2);
    this.currencyId.set(this.CDAI, 2);
    this.currencyId.set(this.USDC, 3);
    this.currencyId.set(this.CUSDC, 3);
    this.currencyId.set(this.WBTC, 4);
    this.currencyId.set(this.CWBTC, 4);
    this.currencyId.set(this.ETH.toLocaleLowerCase(), 1);
    this.currencyId.set(this.CETH.toLocaleLowerCase(), 1);
    this.currencyId.set(this.WETH.toLocaleLowerCase(), 1);
    this.currencyId.set(this.DAI.toLocaleLowerCase(), 2);
    this.currencyId.set(this.CDAI.toLocaleLowerCase(), 2);
    this.currencyId.set(this.USDC.toLocaleLowerCase(), 3);
    this.currencyId.set(this.CUSDC.toLocaleLowerCase(), 3);
    this.currencyId.set(this.WBTC.toLocaleLowerCase(), 4);
    this.currencyId.set(this.CWBTC.toLocaleLowerCase(), 4);
    this.cToken.add(this.CETH);
    this.cToken.add(this.CDAI);
    this.cToken.add(this.CUSDC);
    this.cToken.add(this.CWBTC);
    this.cToken.add(this.CETH.toLowerCase());
    this.cToken.add(this.CDAI.toLowerCase());
    this.cToken.add(this.CUSDC.toLowerCase());
    this.cToken.add(this.CWBTC.toLowerCase());
  }

<<<<<<< HEAD
<<<<<<< HEAD
  static async create(provider: Provider) {
    let notional_bridge_data = new NotionalBridgeData(provider);
    notional_bridge_data.notional = await Notional.load(1, provider);
>>>>>>> 9c917c0b (rebase)
=======
=======
>>>>>>> 6be78da2 (add notional bridge)
  static async create(
    provider: Provider,
  ) {
    let notional_bridge_data = new NotionalBridgeData(provider);
    notional_bridge_data.notional = await Notional.load(1, provider);
<<<<<<< HEAD
>>>>>>> 70661815 (add notional bridge)
=======
>>>>>>> 6be78da2 (add notional bridge)
  }

  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<bigint[]> {
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
    const currencyId = await this.notionalBridgeContract.currencyIds(inputAssetA.erc20Address.toString());
    if (currencyId != 0) {
      const activeMarkets = await this.notionalViewContract.getActiveMarkets(currencyId);
      return [activeMarkets[0].maturity.toBigInt()];
    }
    return [];
=======
    const currencyId = this.currencyId.get(inputAssetA.erc20Address);
    if (currencyId != undefined) {
      const markets = this.notional.system.getMarkets(currencyId);
      return [BigInt(markets[0].maturity)];
    }
    throw "Undefined Currency Id";
>>>>>>> 9c917c0b (rebase)
=======
=======
>>>>>>> 6be78da2 (add notional bridge)
    const currencyId = this.currencyId.get(inputAssetA.erc20Address)
    if (currencyId != undefined) {
      const markets = this.notional.system.getMarkets(currencyId)
      return [BigInt(markets[0].maturity)]
    }
    throw "Undefined Currency Id";
<<<<<<< HEAD
>>>>>>> 70661815 (add notional bridge)
=======
>>>>>>> 6be78da2 (add notional bridge)
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
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
    if (auxData === 0n) {
      const wrappedFcash = IWrappedfCash__factory.connect(inputAssetA.erc20Address.toString(), this.provider);
      const underlyingToken = (await (wrappedFcash.getUnderlyingToken()))._underlyingToken;
      const currencyId = await this.notionalViewContract.getCurrencyId(underlyingToken);
      const [assetAmount, underlyingAmount] =  await this.notionalViewContract.getCashAmountGivenfCashAmount(currencyId, inputValue, 0, Date.now());
      if (outputAssetA.erc20Address.toString() === underlyingToken) {
        return [underlyingAmount.toBigInt()];
      }
      return [assetAmount.toBigInt()];
    }
    const currencyId = await this.notionalViewContract.getCurrencyId(inputAssetA.erc20Address.toString());
    const cashAmount = await this.notionalBridgeContract.computeUnderlyingAmount(inputAssetA.erc20Address.toString(), inputValue);
    const fcashAmount = await this.notionalViewContract.getfCashAmountGivenCashAmount(currencyId,-cashAmount, 0, Date.now());
    return [fcashAmount.toBigInt()];
=======
=======
>>>>>>> 70661815 (add notional bridge)
=======
>>>>>>> 6be78da2 (add notional bridge)
    const tokenCurrencyId = this.currencyId.get(outputAssetA.erc20Address);
    const currentTime = Math.floor(Date.now() / 1000);
    if (auxData === 0n) {
      //redeem
      if (tokenCurrencyId != undefined) {
        const market = this.notional.system.getMarkets(tokenCurrencyId)[0];
<<<<<<< HEAD
<<<<<<< HEAD
        const cashAmount = market.getCashAmountGivenfCashAmount(
          TypedBigNumber.from(inputValue, BigNumberType.InternalUnderlying, market.underlyingSymbol),
          currentTime,
        ).netCashToMarket;
=======
        const cashAmount = market.getCashAmountGivenfCashAmount(TypedBigNumber.from(inputValue, BigNumberType.InternalUnderlying, market.underlyingSymbol),currentTime).netCashToMarket;
>>>>>>> 70661815 (add notional bridge)
=======
        const cashAmount = market.getCashAmountGivenfCashAmount(TypedBigNumber.from(inputValue, BigNumberType.InternalUnderlying, market.underlyingSymbol),currentTime).netCashToMarket;
>>>>>>> 6be78da2 (add notional bridge)
        if (this.cToken.has(outputAssetA.erc20Address)) {
          return [cashAmount.toAssetCash(false).toBigInt()];
        } else {
          return [cashAmount.toUnderlying(false).toBigInt()];
        }
<<<<<<< HEAD
<<<<<<< HEAD
      } else {
        throw "unrecognized currency";
      }
    } else {
      if (tokenCurrencyId != undefined) {
        const market = this.notional.system.getMarkets(tokenCurrencyId)[0];
        if (this.cToken.has(inputAssetA.erc20Address)) {
          const externalAsset = TypedBigNumber.from(
            inputValue.toString(),
            BigNumberType.ExternalAsset,
            market.assetSymbol,
          );
          const cashAmount = market.getfCashAmountGivenCashAmount(externalAsset.toUnderlying(true), currentTime);
          return [cashAmount.abs().toBigInt()];
        } else {
          const externalAsset = TypedBigNumber.from(
            inputValue.toString(),
            BigNumberType.ExternalUnderlying,
            market.underlyingSymbol,
          );
          const cashAmount = market.getfCashAmountGivenCashAmount(externalAsset.toInternalPrecision(), currentTime);
          return [cashAmount.abs().toBigInt()];
        }
      } else {
        throw "unrecognized currency";
      }
    }
>>>>>>> 9c917c0b (rebase)
=======
=======
>>>>>>> 6be78da2 (add notional bridge)
      }
      else {
        throw "unrecognized currency";
      }
    }
    else {
      if (tokenCurrencyId != undefined) {
        const market = this.notional.system.getMarkets(tokenCurrencyId)[0];
        if (this.cToken.has(inputAssetA.erc20Address)) {
          const externalAsset = TypedBigNumber.from(inputValue.toString(), BigNumberType.ExternalAsset, market.assetSymbol);
          const cashAmount = (market.getfCashAmountGivenCashAmount(externalAsset.toUnderlying(true), currentTime));
          return [cashAmount.abs().toBigInt()];
        } else {
          const externalAsset = TypedBigNumber.from(inputValue.toString(), BigNumberType.ExternalUnderlying, market.underlyingSymbol);
          const cashAmount = market.getfCashAmountGivenCashAmount(externalAsset.toInternalPrecision(), currentTime)
          return [cashAmount.abs().toBigInt()];
        }
      }
      else {
        throw "unrecognized currency";
      }
    }
<<<<<<< HEAD
>>>>>>> 70661815 (add notional bridge)
=======
>>>>>>> 6be78da2 (add notional bridge)
  }

  async getMarketSize(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
  ): Promise<AssetValue[]> {
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
    let underlyingToken = inputAssetA.erc20Address.toString();
    if (auxData == 0n) {
      // redeem
      const wrappedFcash = IWrappedfCash__factory.connect(inputAssetA.erc20Address.toString(), this.provider);
      underlyingToken = (await wrappedFcash.getUnderlyingToken())._underlyingToken;
    }
    const currencyId = await this.notionalBridgeContract.currencyIds[underlyingToken];
    const market = await this.notionalViewContract.getActiveMarkets(currencyId)[0];
    if(auxData == 0n){
      return [{assetId: inputAssetA.id  ,amount: market.totalAssetCash.toBigInt()}];
    }
    return [{assetId: inputAssetA.id, amount: market.totalfCash.toBigInt()}];
=======
    const currencyId = this.currencyId.get(inputAssetA.erc20Address);
    let redeem = auxData === 0n;
    if (currencyId != undefined) {
      const markets = this.notional.system.getMarkets(currencyId);
      if (redeem) {
        return [
          {
            assetId: inputAssetA.id,
            amount: BigInt(markets[0].totalfCashDisplayString),
          },
        ];
      }
      return [
        {
          assetId: inputAssetA.id,
          amount: BigInt(markets[0].totalCashUnderlyingDisplayString),
        },
      ];
    }
    throw "Undefined Currency Id";
>>>>>>> 9c917c0b (rebase)
=======
=======
>>>>>>> 6be78da2 (add notional bridge)
    const currencyId = this.currencyId.get(inputAssetA.erc20Address)
    let redeem = auxData === 0n
    if (currencyId != undefined) {
      const markets = this.notional.system.getMarkets(currencyId)
      if (redeem) {
        return [{
          assetId: inputAssetA.id,
          amount: BigInt(markets[0].totalfCashDisplayString)
        }]
      }
      return [{
        assetId: inputAssetA.id,
        amount: BigInt(markets[0].totalCashUnderlyingDisplayString)
      }]
    }
    throw "Undefined Currency Id";

<<<<<<< HEAD
>>>>>>> 70661815 (add notional bridge)
=======
>>>>>>> 6be78da2 (add notional bridge)
  }
}
