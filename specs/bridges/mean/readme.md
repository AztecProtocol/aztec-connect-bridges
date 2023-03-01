# Spec for Mean Finance Bridge

## What does the bridge do? Why did you build it?

The bridge allows a user to enter a DCA (Dollar Cost Average) position, selling one asset and buying another over a period of time.

## What protocol(s) does the bridge interact with?

The bridge interacts only with Mean Finance. In particular, we interact with two different contracts:
1. The DCA Hub: does everything related to DCAing
2. The Transformer Registry: can transform between wrapped tokens and their underlying tokens

Both are immutable. However, the Transformer Registry is in fact a registry and the Mean Finance team has the ability to modify entries

## What is the flow of the bridge?

The bridge is synchronous, and it has two possible actions: the deposit, and the withdraw.

### Deposit (L2)

When users create a DCA position, they must specify:
- The "from" token
- The "to" token
- Amount of "from" token
- Swap interval (daily, weekly, etc)
- Amount of swaps

Also, the bridge supports the ability to generate yield while the DCA position is executed (both on the "from" and "to" tokens)

When a deposit is executed, the user will get back a virtual asset that represents the created position. The amount of "virtual asset" that they get will represent their share in the batch they were a part of.

### Withdraw (L2)

For a position to be withdrawn, all its available funds must have been sold for the opposite asset (there are some exceptions described below). When withdrawn, the swapped funds will be returned to the bridge and the user may claim them on L2. 

Until all funds of the batch are claimed, they will remain on the bridge. In the case of yield-bearing tokens, they will remain wrapped (and continue to earn yield) until they are claimed by the owner

### Diagram
![Flow diagram](FlowDiagram.png)

### Technical details
#### In the case of deposit
This is how we expect the data to be passed to the bridge:
- `inputAssetA` will represent the token that the user will deposit (for example DAI)
- `outputAssetA` will be the virtual asset

#### In the case of withdraw
This is how we expect the data to be passed to the bridge:
- `inputAssetA` will be the virtual asset
- `outputAssetA` will be asset that the tokens were swapped for
- `outputAssetB` will be asset that was originally deposited

#### In both cases 
The `auxData` field is 64bits long:
- First 24 bits: amount of swaps
- Next 8 bits: swap interval code (we map the values between 0 and 7 to a swap interval)
- Next 16 bits: token id for the "from" token
- Last 16 bits: token id for the "to" token

## Please list any edge cases that may restrict the usefulness of the bridge or that the bridge explicitly prevents.

### Preparation
In order for swaps to work, tokens need to be registered on the smart contract. This will give the rollup and the DCA Hub max allowance to work correctly.

This configuration is permissionless and anyone can execute them.

### Edge cases
There are two scenarios where the swaps might not be executed:

1. If all swaps are paused (this would happen in the case of a vulnerability)
1. If one of the tokens in the positions is no longer allowed

In any of these scenarios, users will be able to withdraw both the swapped and unswapped funds back to L2.

## How can the accounting of the bridge be impacted by interactions performed by other parties than the bridge?

The accounting could only be impacted by a vulnerability on Mean Finance's side. If this doesn't happen, then everything should work as expected.

## Is this contract upgradable? If so, what are the restrictions on upgradability?

The contract is immutable, but there is an owner. The owner can only set and modify subsidies for certain pairs.

## Does this bridge maintain state? If so, what is stored and why?

The bridge maintains the following state:
- A registry for supported tokens
- The association between user interaction and DCA position
- The amount of funds for each terminated position