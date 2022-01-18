import { AlphaRouter } from '@uniswap/smart-order-router'
import { Token, CurrencyAmount, TradeType, Percent } from '@uniswap/sdk-core'
import { BaseProvider } from 'ethers/node_modules/@ethersproject/providers';
import { Signer } from 'ethers';

const V3_SWAP_ROUTER_ADDRESS = '0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45';

export class Router {
  private readonly router: AlphaRouter;

  constructor(chainId: number, private provider: BaseProvider, private address: string) {
    this.router = new AlphaRouter({ chainId, provider });
  }

  async route(tokens: Token[], inputAmount: bigint, from: string) {
   
    const inputCurrency = CurrencyAmount.fromRawAmount(tokens[0], inputAmount.toString());
    
    const route = await this.router.route(
      inputCurrency,
      tokens[1],
      TradeType.EXACT_INPUT,
      {
        recipient: this.address,
        slippageTolerance: new Percent(5, 100),
        deadline: 100
      }
    );

    console.log("Route ", route);

    if (!route) {
      return;
    }

    console.log(`Quote Exact In: ${route?.quote.toFixed(2)}`);
    console.log(`Gas Adjusted Quote In: ${route?.quoteGasAdjusted.toFixed(2)}`);
    console.log(`Gas Used USD: ${route?.estimatedGasUsedUSD.toFixed(6)}`);

    const transaction = {
      data: route?.methodParameters?.calldata!,
      to: V3_SWAP_ROUTER_ADDRESS,
      value: BigInt(route?.methodParameters?.value!),
      from,
      gasPrice: BigInt(route.gasPriceWei.toString()),
    };
    return transaction;
  }
}