# Spec for Notional Bridge

## What does the bridge do? Why build it?

The bridge deposits into Notional.Finance to receive `fcash` a derivative that represents the lending position of the corresponding underlying token. We build it to allow users to earn yield on their assets.

## What protocol(s) does the bridge interact with ?

The bridge interacts with one protocols, namely Notional.Finance.

[Notional.Finance](https://notional.finance/) is a project that supports lending and borrowing. They allow users to deposit assets (USDC, ETH, DAI, WBTC) and receive the corresponding `fcash` tokens to get interests for their asset tokens.

## What is the flow of the bridge?

There are two flows of Notional Bridge, namely deposits and withdraws.

### Deposit

If the bridge received `USDC`, `DAI`, `ETH`, `WBTC` or their corresponding compound tokens, and the output asset address matches the address of `fcash` token we compute, then the bridge would deposit the input token into the `fcash` contract and give back a certain number of `fcash` tokens to represent the lending position. 

### Withdrawal

If the bridge receives `fcash` as the input token, it will withdraw them for the corresponding asset token.(NOTICE: it accepts any slippage). If the output token is eth, it will then transfer the eth received to the `ROLLUP_PROCESSOR` for the given `interactionNonce`. If not, the bridge will approve `ROLLUP_PROCESSOR` to transfer it.

### General Properties for both deposit and withdrawal

- The bridge is synchronous, and will always return `isAsync = false`.

- The bridge uses `auxData` for entering positions. `auxData` represents the maturity of the market we want to enter


## Is the contract upgradeable?

No, the bridge is immutable without any admin role.
