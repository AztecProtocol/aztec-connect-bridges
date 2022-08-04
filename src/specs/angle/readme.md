# Aztec Connect Bridges Specification Template

## What does this bridge do? Why did you build it?

The bridge allows a user to deposit ERC20 tokens to Angle Protocol and receive in exchange sanTokens (yield bearing tokens).
It is build to allow users to earn yield on their tokens.

## What protocol(s) does the bridge interact with?

The bridge interacts with [Angle Protocol](https://angle.money/).
Angle is the first decentralized, capital efficient and over-collateralized stablecoin protocol.
[Angle's Github](https://github.com/AngleProtocol/app)

## What is the flow of the bridge?

There are 2 flows:

- deposit ERC20 and receive sanTokens (yield bearing)
- withdraw ERC20 (by sending back your sanTokens)

Input tokens currently accepted by Angle are: DAI, USDC, wETH and FRAX.

## What functions are available in [/src/client](./client)?

Main functions are `getAuxData` and `getExpectedOutput`.
`getAuxData` returns the correct `auxData` to be passed to the bridge contract based on input and output assets.
`getExpectedOutput` returns the expected amount of ERC20 returns from a deposit or a withdraw to Angle Protocol.

## Is this contract upgradable? If so, what are the restrictions on upgradability?

No, bridge is immutable.

## Does this bridge maintain state? If so, what is stored and why?

No state needed.
