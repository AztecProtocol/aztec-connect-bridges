# Dollar Cost Averaging Bridge

## What does the bridge do? Why did you build it?

The bridge allows a user to enter a DCA (Dollar Cost Average) position, selling one asset and buying another over a period of time.

## What protocol(s) does the bridge interact with?

Strictly speaking, the bridge implements a DCA protocol itself and has the ability to operate given only a pricing oracle (Chainlink).
However, this requires external parties to trade with the bridge, so an alternative using Uniswap V3 is also outlined.

- [ChainLink](https://chain.link/)
- [Uniswap V3](https://uniswap.org/)

## What is the flow of the bridge?

The bridge is asynchronous and primarily have one flow from inside the Aztec Connect rollup, the deposit.
However, it allows a number of operations to be executed directly from layer 1 by other parties for proper functioning.
The bridge allows for DCA positions in both directions, e.g., A -> B and B -> A.

### Deposit (L2)

A user deposits funds into the bridge, providing the length (in ticks) that his positions should unfold over as auxdata.
A position is initially stored as start/end tick and the amount of funds that are to be traded at each tick.
The overall tick will be increased by the amount deposited.

To stabilise gas used by deposits, the storage slots to be used can be "poked" by using the `pokeNextTicks` and `pokeTicks` functions.
With storage poked, the gas varies depending on the length of the DCA position, but ~80K for 7 days + gas for token transfers.

### Rebalancing (L1)

The system has two ways to rebalance.
Either by trading with L1 users or by Uniswap v3 as the counterparty.

For both rebalancing acts, the bridge will first perform internal rebalancing.
Here it will rebalance using the A and B funds for the tick, matching them against each other using the price at the tick (chainlink oracle value or interpolated).

L1 users trading with the bridge can trade using the current price (chainlink oracle) for whatever amount is in excess (e.g., with 100 Dai in excess at a 1000 dai/eth price, he can sell 0.1 eth to the bridge for the 100 dai).
The price has no slippage, and is sold at the current oracle price.
This means that when oracle lags behind actual price, it is possible to arb it.

It is also possible to have the contract trade directly on uniswap itself.
This can be triggered by anyone, and will essentially perform 3 inner rebalance, first inside each tick, then across the ticks with itself, and finally using the excess on uniswap.
To limit slippage, it computes a minimum amount received using the oracle price (we already use the value, so slippage protection comes cheaply).

The flows reverts if the oracle price is stale (have not updated within the last 24 hours), or if the price goes negative.
When using the chainlink oracle, this is centralization issue as chainlink could kill the bridge through the oracle.

### Finalise (L1)

A position needs to be finalised before it can be exited.
For a position to be ready to be finalised, all its available funds must have been sold for the opposite asset.
When finalised, the accumulated funds will be returned to the bridge and the user may claim them on L2.
To incentivise searchers on L1 to finalise the transactions, a fraction of the swapped assets are paid to the initiator of the transaction (`tx.origin` instead of `msg.sender` as the rollup will always be the `msg.sender` and we cannot pass any address along).

## Please list any edge cases that may restrict the usefulness of the bridge or that the bridge explicitly prevents.

- Stale or negative price from oracle (chainlink can essentially turn off the bridge while funds are in it).
- Uniswap flow might revert if price impact and slippage is too large
- If there are only a few users of the bridge, there will be only few prices stored, relying more on interpolation

## How can the accounting of the bridge be impacted by interactions performed by other parties than the bridge?

Tokens are not deposited into a separate contract, so unless the tokens used are malicious, balances should not be impacted.

## Is this contract upgradable? If so, what are the restrictions on upgradability?

The contract is immutable.

## Does this bridge maintain state? If so, what is stored and why?

The bridge maintains state of the individual DCA positions and the aggregated ticks.

## Any other relevant information

To function optimally, the bridge relies on external parties coming in to arb it.
