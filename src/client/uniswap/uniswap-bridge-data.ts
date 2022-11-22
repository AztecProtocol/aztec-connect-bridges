import { AuxDataConfig, AztecAsset, AztecAssetType, BridgeDataFieldGetters, SolidityType } from "../bridge-data";

import { EthAddress } from "@aztec/barretenberg/address";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { BridgeCallData } from "@aztec/barretenberg/bridge_call_data";
import { BigNumber } from "ethers";
import "isomorphic-fetch";
import {
  IChainlinkOracle,
  IChainlinkOracle__factory,
  UniswapBridge,
  UniswapBridge__factory,
} from "../../../typechain-types";
import { createWeb3Provider } from "../aztec/provider";

export class UniswapBridgeData implements BridgeDataFieldGetters {
  private readonly WETH = EthAddress.fromString("0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2");
  private readonly USDC = EthAddress.fromString("0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48");
  private readonly DAI = EthAddress.fromString("0x6B175474E89094C44Da98b954EedeAC495271d0F");

  private readonly UNUSED_PATH: UniswapBridge.SplitPathStruct = {
    percentage: 0,
    fee1: 0,
    token1: EthAddress.ZERO.toString(),
    fee2: 0,
    token2: EthAddress.ZERO.toString(),
    fee3: 0,
  };

  private readonly ETH_DAI_PATH: UniswapBridge.SplitPathStruct = {
    percentage: 100,
    fee1: 500,
    token1: this.USDC.toString(),
    fee2: 100, // Ignored since unused
    token2: EthAddress.ZERO.toString(),
    fee3: 100,
  };

  private readonly DAI_ETH_PATH: UniswapBridge.SplitPathStruct = {
    percentage: 100,
    fee1: 100,
    token1: this.USDC.toString(),
    fee2: 100, // Ignored since unused
    token2: EthAddress.ZERO.toString(),
    fee3: 500,
  };

  // 0000000000000000000000000011111111111111111111111111111111111111
  public readonly PATH_MASK = 274877906943n;
  private readonly PRICE_SHIFT = 38n; // Price is encoded in the left-most 26 bits of auxData
  private readonly EXPONENT_MASK = 31n; // 00000000000000000000011111
  private readonly SIGNIFICAND_SHIFT = 5n; // Significand is encoded in the left-most 21 bits of price

  public readonly MAX_ACCEPTABLE_SLIPPAGE = 500n; // Denominated in basis points
  public readonly IDEAL_SLIPPAGE = 200n; // Denominated in basis points

  private constructor(
    private bridgeAddressId: number,
    private uniswapBridge: UniswapBridge,
    private daiEthOracle: IChainlinkOracle,
  ) {}

  static create(provider: EthereumProvider, bridgeAddressId: number, bridgeAddress: EthAddress) {
    const ethersProvider = createWeb3Provider(provider);
    const uniswapBridge = UniswapBridge__factory.connect(bridgeAddress.toString(), ethersProvider);
    const chainlinkEthDaiOracle = IChainlinkOracle__factory.connect(
      "0x773616E4d11A78F511299002da57A0a94577F1f4",
      ethersProvider,
    );
    return new UniswapBridgeData(bridgeAddressId, uniswapBridge, chainlinkEthDaiOracle);
  }

  /**
   * @param inputAssetA A struct detailing the token to swap
   * @param inputAssetB Not used
   * @param outputAssetA A struct detailing the token to receive
   * @param outputAssetB Not used
   * @return The set of possible auxData values that they can use for a given set of input and output assets
   * @dev This function currently only works with hardcoded paths:
   *                           500     100
   *      ETH -> DAI path: ETH -> USDC -> DAI
   */
  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<bigint[]> {
    let splitPath: UniswapBridge.SplitPathStruct;
    if (
      (inputAssetA.assetType === AztecAssetType.ETH || inputAssetA.erc20Address.equals(this.WETH)) &&
      outputAssetA.erc20Address.equals(this.DAI)
    ) {
      splitPath = this.ETH_DAI_PATH;
    } else if (
      inputAssetA.erc20Address.equals(this.DAI) &&
      (outputAssetA.assetType === AztecAssetType.ETH || outputAssetA.erc20Address.equals(this.WETH))
    ) {
      splitPath = this.DAI_ETH_PATH;
    } else {
      throw "The combination of input/output assets not supported";
    }

    const [, daiPrice, , ,] = await this.daiEthOracle.latestRoundData();
    const oraclePrice = inputAssetA.erc20Address.equals(this.DAI)
      ? daiPrice.toBigInt()
      : BigNumber.from("1000000000000000000000000000000000000").div(daiPrice).toBigInt();
    const priceMaxSlippage = (oraclePrice * (10000n - this.MAX_ACCEPTABLE_SLIPPAGE)) / 10000n;
    const priceIdealSlippage = (oraclePrice * (10000n - this.IDEAL_SLIPPAGE)) / 10000n;

    // Now convert the price to a format used by the bridge
    // Bridge's encoding function works with `amountIn` and `minAmountOut` to encode the price so we'll pass it in in
    // that format --> we set `amountIn` in such a way that we `minAmountOut` can be equal to `priceIdealSlippage`
    const amountIn = 10n ** 18n; // 1 ETH or 1 DAI on input
    const minAmountOut = priceIdealSlippage;

    const auxDataIdealSlippage = (
      await this.uniswapBridge.encodePath(
        amountIn,
        minAmountOut,
        inputAssetA.assetType === AztecAssetType.ETH ? this.WETH.toString() : inputAssetA.erc20Address.toString(),
        splitPath,
        this.UNUSED_PATH,
      )
    ).toBigInt();

    const relevantBridgeCallDatas = await this.fetchRelevantBridgeCallData(
      this.bridgeAddressId,
      inputAssetA.id,
      outputAssetA.id,
      auxDataIdealSlippage & this.PATH_MASK,
    );

    // 1. Check if there is an interaction with acceptable minPrice --> acceptable minPrice is defined as a price
    //    which is smaller than current oracle price  and bigger than current oracle price with max slippage
    for (const data of relevantBridgeCallDatas) {
      const existingBatchPrice = this.decodePrice(data.auxData);
      if (priceMaxSlippage < existingBatchPrice && existingBatchPrice < oraclePrice) {
        return [data.auxData];
      }
    }

    // 2. If no acceptable auxData was found return a custom one
    return [auxDataIdealSlippage];
  }

  public auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: "Encoded swap path and min price",
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
    const inputAddr = inputAssetA.assetType === AztecAssetType.ETH ? this.WETH : inputAssetA.erc20Address;
    const outputAddr = outputAssetA.assetType === AztecAssetType.ETH ? this.WETH : outputAssetA.erc20Address;

    const quote = await this.uniswapBridge.callStatic.quote(
      inputValue,
      inputAddr.toString(),
      auxData,
      outputAddr.toString(),
    );

    return [quote.toBigInt()];
  }

  private async fetchRelevantBridgeCallData(
    bridgeAddressId: number,
    inputAssetIdA: number,
    outputAssetIdA: number,
    encodedPath: bigint,
  ): Promise<BridgeCallData[]> {
    const result = await (
      await fetch("https://api.aztec.network/aztec-connect-prod/falafel/status", {
        method: "GET",
        headers: {
          "Content-Type": "application/json",
        },
      })
    ).json();

    const bridgeCallDatas: BridgeCallData[] = result.bridgeStatus.map((status: any) =>
      BridgeCallData.fromString(status.bridgeCallData),
    );

    return bridgeCallDatas.filter(
      (data: BridgeCallData) =>
        data.bridgeAddressId === bridgeAddressId &&
        data.inputAssetIdA === inputAssetIdA &&
        data.outputAssetIdA === outputAssetIdA &&
        (data.auxData & this.PATH_MASK) === encodedPath,
    );
  }

  public decodePrice(auxData: bigint): bigint {
    const encodedPrice = auxData >> this.PRICE_SHIFT;
    const significand = encodedPrice >> this.SIGNIFICAND_SHIFT;
    const exponent = encodedPrice & this.EXPONENT_MASK;
    return significand * 10n ** exponent;
  }
}
