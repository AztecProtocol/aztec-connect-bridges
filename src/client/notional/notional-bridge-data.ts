import { AssetValue, AuxDataConfig, AztecAsset, BridgeDataFieldGetters, SolidityType } from "../bridge-data";
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
  }

  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<bigint[]> {
    const currencyId = await this.notionalBridgeContract.currencyIds(inputAssetA.erc20Address.toString());
    if (currencyId != 0) {
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
    const currencyId = await this.notionalBridgeContract.currencyIds[underlyingToken];
    const market = await this.notionalViewContract.getActiveMarkets(currencyId)[0];
    if(auxData == 0n){
      return [{assetId: inputAssetA.id  ,amount: market.totalAssetCash.toBigInt()}];
    }
    return [{assetId: inputAssetA.id, amount: market.totalfCash.toBigInt()}];
  }
}