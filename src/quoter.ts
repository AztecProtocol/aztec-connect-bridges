import { abi as QuoterABI } from "@uniswap/v3-periphery/artifacts/contracts/lens/Quoter.sol/Quoter.json";
import { Contract, BigNumber } from "ethers";
import { Provider } from "@ethersproject/providers";
import { Pool } from "@uniswap/v3-sdk";
import { CurrencyAmount, Token, TradeType } from "@uniswap/sdk-core";
import { abi as IUniswapV3PoolABI } from "@uniswap/v3-core/artifacts/contracts/interfaces/IUniswapV3Pool.sol/IUniswapV3Pool.json";
import { Route } from "@uniswap/v3-sdk";
import { Trade } from "@uniswap/v3-sdk";

interface Immutables {
  factory: string;
  token0: string;
  token1: string;
  fee: number;
  tickSpacing: number;
  maxLiquidityPerTick: BigNumber;
}

interface State {
  liquidity: BigNumber;
  sqrtPriceX96: BigNumber;
  tick: number;
  observationIndex: number;
  observationCardinality: number;
  observationCardinalityNext: number;
  feeProtocol: number;
  unlocked: boolean;
}


export class Quoter {
  private quoterContract: Contract;
  private poolContract: Contract;
  private readonly quoterAddress = "0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6";
  private readonly poolAddress = "0x88e6a0c2ddd26feeb64f039a2c41296fcb3f5640";

  constructor(private provider: Provider) {
    this.quoterContract = new Contract(this.quoterAddress, QuoterABI, provider);
    this.poolContract = new Contract(
      this.poolAddress,
      IUniswapV3PoolABI,
      this.provider
    );
  }

  public async getPoolDetails() {      
      const [factory, token0, token1, fee, tickSpacing, maxLiquidityPerTick] =
      await Promise.all([
        this.poolContract.factory(),
        this.poolContract.token0(),
        this.poolContract.token1(),
        this.poolContract.fee(),
        this.poolContract.tickSpacing(),
        this.poolContract.maxLiquidityPerTick(),
      ]);

    const immutables: Immutables = {
      factory,
      token0,
      token1,
      fee,
      tickSpacing,
      maxLiquidityPerTick,
    };
    return immutables;
  }

  public async getPoolState() {
    // note that data here can be desynced if the call executes over the span of two or more blocks.
    const [liquidity, slot] = await Promise.all([
      this.poolContract.liquidity(),
      this.poolContract.slot0(),
    ]);
  
    const poolState: State = {
      liquidity,
      sqrtPriceX96: slot[0],
      tick: slot[1],
      observationIndex: slot[2],
      observationCardinality: slot[3],
      observationCardinalityNext: slot[4],
      feeProtocol: slot[5],
      unlocked: slot[6],
    };
  
    return poolState;
  }

  public async quote(tokens:Token[], fee: number, state: State, inputAmount: bigint) {
    // create an instance of the pool object for the given pool
    const poolExample = new Pool(
      tokens[0],
      tokens[1],
      fee,
      state.sqrtPriceX96.toString(), //note the description discrepancy - sqrtPriceX96 and sqrtRatioX96 are interchangable values
      state.liquidity.toString(),
      state.tick
    );

    // call the quoter contract to determine the amount out of a swap, given an amount in
    const quotedAmountOut = await this.quoterContract.callStatic.quoteExactInputSingle(
      tokens[0].address,
      tokens[1].address,
      fee,
      inputAmount.toString(),
      0
    );

    // create an instance of the route object in order to construct a trade object
    const swapRoute = new Route([poolExample], tokens[0], tokens[1]);

    const inputCurrency = CurrencyAmount.fromRawAmount(tokens[0], inputAmount.toString());
    const outputCurrency = CurrencyAmount.fromRawAmount(tokens[1], quotedAmountOut.toString());

    // create an unchecked trade instance
    const uncheckedTradeExample = await Trade.createUncheckedTrade({
      route: swapRoute,
      inputAmount: inputCurrency,
      outputAmount: outputCurrency,
      tradeType: TradeType.EXACT_INPUT,
    });
    
    console.log("Swap route", swapRoute);
    console.log("Input Currency", inputCurrency);
    console.log("Output Currency", outputCurrency);
    console.log("The quoted amount out is", quotedAmountOut.toString());
    console.log("The unchecked trade object is", uncheckedTradeExample);
  }
}