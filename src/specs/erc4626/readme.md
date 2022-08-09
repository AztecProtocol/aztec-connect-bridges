# Spec for ERC4626 Bridge

## What does this bridge do? Why did you build it?

The bridge allows people to issue and redeem shares of any ERC4626 vault after the vault is listed in the contract.

## What protocol(s) does the bridge interact with?

Any ERC4626 compatible vault and the underlying assets.

## What is the flow of the bridge?

The bridge only support 2 flows:

1. ERC4626 share issuance (this flow gets triggered when `_auxData` = 0),
2. ERC4626 share redemption (this flow gets triggered when `_auxData` = 1).

## Please list any edge cases that may restrict the usefulness of the bridge or that the bridge explicitly prevents.

Vault has to be listed first before using the bridge with it.

## How can the accounting of the bridge be impacted by interactions performed by other parties than the bridge? Example, if borrowing, how does it handle liquidations etc.

The only state the contract works with are the approvals of share and asset tokens.
The only time this could cause any damage is if we use the EIP-1087 based optimization of seeding bridge's token balances to non-zero values and then a hacker would set approvals on his hacker vault and steal that non-zero balance.
This would cause the bridge to suddenly be 15k gas more expensive to use which could cause the interactions to run out of cas.
This is a griefing attack since the hacker would not gain any value (e.g. 1 wei of WETH is way more costly to steal than is its value).

## Is this contract upgradable? If so, what are the restrictions on upgradability?

The contract is immutable and have no admin controls at all.

## Does this bridge maintain state? If so, what is stored and why?

The bridge doesn't store any state.
