import {
    AssetValue,
    AuxDataConfig,
    AztecAsset,
    SolidityType,
    AztecAssetType,
    YieldBridgeData,
  } from '../bridge-data';
  
import {
      NotionalLendingBridge, NotionalViews, IERC20Detailed, CTokenInterface, FCashToken, FCashToken__factory, CTokenInterface__factory
} from "../../../typechain-types"
import { BigNumber } from 'ethers';
import { AssetRateParametersStructOutput } from '../../../typechain-types/NotionalProxy';

export class NotionalBridgeData implements YieldBridgeData {
    currencyID = new Map<string, number>();
    NotionalBridge : NotionalLendingBridge
    NotionalView: NotionalViews
    ZERO_ADDRESS: string = "0x00000000000000000000000000000000000000"
    

    constructor(NotionalBridge: NotionalLendingBridge, NotionalView: NotionalViews) {
      this.NotionalBridge = NotionalBridge;
      this.NotionalView = NotionalView;
      const ETH = this.ZERO_ADDRESS;
      const CETH = "0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5";
      const DAI = "0x6B175474E89094C44Da98b954EedeAC495271d0F";
      const CDAI = "0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643";
      const USDC = "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48";
      const CUSDC = "0x39AA39c021dfbaE8faC545936693aC917d5E7563";
      const WBTC = "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599";
      const CWBTC = "0xC11b1268C1A384e55C48c2391d8d480264A3A7F4";
      this.currencyID.set(ETH, 1);
      this.currencyID.set(CETH,1);
      this.currencyID.set(DAI, 2);
      this.currencyID.set(CDAI, 2);
      this.currencyID.set(USDC,3);
      this.currencyID.set(CUSDC, 3);
      this.currencyID.set(WBTC,4);
      this.currencyID.set(CWBTC,4);
     }
    
    public auxDataConfig: AuxDataConfig[] = [
      {
        start: 0,
        length: 64,
        solidityType: SolidityType.uint64,
        description: 'the most significant 16 bits represent the currencyId, and the follwing 8 bits represent marketId',
      },
    ];
  
    // Lido bridge contract is stateless
    async getInteractionPresentValue(interactionNonce: bigint): Promise<AssetValue[]> {
      return [];
    }
  
    async getAuxData(
      inputAssetA: AztecAsset,
      inputAssetB: AztecAsset,
      outputAssetA: AztecAsset,
      outputAssetB: AztecAsset,
    ): Promise<bigint[]> {
        let auxData: bigint
        const marketId = 1;
        if (inputAssetA.assetType != AztecAssetType.NOT_USED){
            const currency = this.currencyID.get(inputAssetA.erc20Address);
            auxData = (BigInt(currency) << 48n) +(BigInt(marketId) << 40n);
        } else {
            const cashToken = await this.NotionalBridge.fcashTokenCashToken(inputAssetA.erc20Address);
            if (cashToken != this.ZERO_ADDRESS) {
              const currency = this.currencyID.get(cashToken)
              auxData = (BigInt(currency) << 48n) +(BigInt(marketId) << 40n);
            }
        }
      return [auxData]
    }
    
    async computeUnderlyingAmount(underlyingAddr: IERC20Detailed, cToken:CTokenInterface, inputAmt: bigint, isCToken: boolean): 
    Promise<bigint> {
      const underlyingDecimal = underlyingAddr.address == this.ZERO_ADDRESS ? 18n : BigInt((await underlyingAddr.decimals()).toString());
      let cashAmt: bigint
      if (isCToken) {
          const exchangeRateCurrent =BigInt((await cToken.exchangeRateStored()).toString());
          const mantissa = 10n + underlyingDecimal;
          cashAmt = inputAmt * exchangeRateCurrent/(10n ** mantissa);
      }  else{
          cashAmt = inputAmt / (10n ** (underlyingDecimal-8n));
      }
      return cashAmt
    }


    convertFromUnderlying(ar: AssetRateParametersStructOutput, underlyingBalance: bigint) {
      const ASSET_RATE_DECIMAL_DIFFERENCE = 1e10;
      const assetBalance = ((BigNumber.from(underlyingBalance).mul(ASSET_RATE_DECIMAL_DIFFERENCE)).mul(ar.underlyingDecimals)).div(ar.rate);
      return assetBalance;
    }

    async getExpectedOutput(
      inputAssetA: AztecAsset,
      inputAssetB: AztecAsset,
      outputAssetA: AztecAsset,
      outputAssetB: AztecAsset,
      auxData: bigint,
      inputValue: bigint,
    ): Promise<bigint[]> {
      // CashToken/UnderlyingToken -> FCashToken
      let [index,isCToken] = await(this.NotionalBridge.findToken(inputAssetA.erc20Address))
      let ret_val : bigint
      if (index.toNumber() != -1){
        const blockTime = (await this.NotionalBridge.provider.getBlock("latest")).timestamp
        const currency = this.currencyID.get(inputAssetA.erc20Address);
        const cashAmt = await this.computeUnderlyingAmount(await this.NotionalBridge.underlyingTokens[Number(index)], await this.NotionalBridge.cTokens[Number(index)], inputValue, isCToken);
        const fCashAmt = await (this.NotionalView).getfCashAmountGivenCashAmount(currency, -cashAmt, 1, blockTime)
        ret_val = BigInt(fCashAmt.toString())
      } else {
        // FCashToken -> CashToken/UnderlyingToken
        const fcashContract: FCashToken = FCashToken__factory.connect(inputAssetA.erc20Address, this.NotionalBridge.provider)
        const maturity =  await fcashContract.maturity()
        const blockTime = (await this.NotionalBridge.provider.getBlock("latest")).timestamp
        const cashToken = await this.NotionalBridge.fcashTokenCashToken(inputAssetA.erc20Address)
        const currency = this.currencyID.get(cashToken)
        if (blockTime < maturity.toNumber()) {
          const [cashAmt, underlyingAmt] = await this.NotionalView.getCashAmountGivenfCashAmount(currency, inputValue, inputValue, blockTime)
          isCToken = await this.NotionalBridge.findToken(cashToken)[1]
          ret_val = isCToken ?  cashAmt.toBigInt() : underlyingAmt.toBigInt()
        } else {
          const ar = await this.NotionalView.getSettlementRate(currency, maturity)
          const cOutputAmount =  this.convertFromUnderlying(ar, inputValue);
          index = await this.NotionalBridge.findToken(cashToken)[0]
          const cashTokenContract = CTokenInterface__factory.connect(cashToken, this.NotionalBridge.provider)
          const underlyingAmt = await this.computeUnderlyingAmount(await this.NotionalBridge.underlyingTokens[index.toNumber()], cashTokenContract,cOutputAmount.toBigInt(), true)
          ret_val = isCToken ? cOutputAmount.toBigInt() : underlyingAmt
        }
      }
      return [ret_val];
    }

    // not applicable
    async getExpectedYearlyOuput(
      inputAssetA: AztecAsset,
      inputAssetB: AztecAsset,
      outputAssetA: AztecAsset,
      outputAssetB: AztecAsset,
      auxData: bigint,
      precision: bigint,
    ): Promise<bigint[]> {
      return [0n]
    }
  
    async getMarketSize(
      inputAssetA: AztecAsset,
      inputAssetB: AztecAsset,
      outputAssetA: AztecAsset,
      outputAssetB: AztecAsset,
      auxData: bigint,
    ): Promise<AssetValue[]> {
      const currencyId = this.currencyID.get(inputAssetA.erc20Address);
      const market = (await this.NotionalView.getActiveMarkets(currencyId))[0]
      const assetValue = market.totalAssetCash
      return [
        {
          assetId: inputAssetA.id,
          amount: assetValue.toBigInt(),
        }]
    }
  }
  