# Spec for Trove Bridge

## What does the bridge do? Why build it?
The bridge allows user to borrow LUSD by depositing ETH as collateral.

## What protocol(s) does the bridge interact with ?
This bridge interacts with Liquity and Uniswap V3 protocols.
Uniswap is used when user wants to repay debt with collateral (ETH is "flash swapped" to LUSD, debt gets repaid,
collateral withdrawn, flash swap gets paid for with withdrawn collateral).

## What is the flow of the bridge?
There are 3 flows supported by the bridge: borrowing, repaying and redeeming.

> Note: Before the bridge gets used someone has to open the bridge's Trove by calling bridge's `openTrove` function.

### Borrowing
Borrowing flow is simple.
User provides ETH on the input and gets LUSD on the ouput (+ accounting token used to rerpresent user's collateral and
debt).
Since the collateral ratio is fixed by the bridge, user gets the amount of LUSD out based only on the amount
of collateral provided and the collateral ratio.
The borrowing interaction would revert in case the bridge's Trove is not active.

> Note: Fixed collateral ratio in this case means that no user can ever move the collateral ratio of the bridge's Trove.

### Repaying

There are 3 repaying "subflows":
1. Repaying with LUSD -> User provides LUSD (and accounting token) on input and gets the full amount of collateral
originally provided,
2. Repaying with collateral -> User repays the debt with collateral using flash swaps.
3. Repaying with a combination of LUSD and collateral -> This flow gets executed when the Trove managed by the bridge 
was part of a [redistribution](https://www.liquity.org/features/efficient-liquidations).
In such a case 1 accounting token corresponds to more than one LUSD worth of debt.
Due to limitations of Aztec Connect both input tokens have the same amount on the input.
This means that it's currently impossible to provide more of LUSD than accounting token on input which means that
in that not enough LUSD was provided to repay the debt in full.
For this reason flash swap of a part of user's collateral is performed.
This is an edge case scenario which might never occur.

> Note: Currently only the second subflow is used (repaying with collateral) because it turned out to be complicated
to provide the same amount of input tokens on the input (for that we would need user to have notes of the same value
of both tokens -> this basically never happens which means that user would need to first split one of her notes ->
this would require a standalone transaction and user would have to wait for the tx to be settled -> this is a horrible
UX, so we've decided to currently only support the subflow 2 on the zk.money).

### Redeeming
This is a flow which gets executed when the Trove was closed by redemption (see [liquity blog](https://www.liquity.org/blog/understanding-liquitys-redemption-mechanism) for explanation).
In such a scenario user only provides accounting token on the input and receives the remaining collateral on the output.

### General Properties of flows

- The bridge is synchronous, and will always return `isAsync = false`.

- The bridge uses an `auxData` to pass in the maximum borrower fee during the borrowing flow or max price during
the repaying with collateral flow and repaying after redistribution flows.
For repaying with LUSD and redeeming flows `auxData` is unused. 

- The Bridge perform token pre-approvals in the `openTrove` function.

## How many Troves does 1 bridge controls?
1 deployment of the bridge contract controls 1 trove.
The bridge keeps precise accounting of debt by making sure that no user can change the trove's ICR.
This means that when a price goes down the only way how a user can avoid liquidation penalty is to repay their debt.
This is limiting and a bit unfortunate since borrowing fee gets paid only once and that is during borrowing.

## Other relevant info

## Liquidation
In case the trove gets liquidated, the bridge no longer controls any ETH and all the TB balances are irrelevant.
At this point the bridge is defunct (unless owner is the only one who borrowed).
If owner is the only who borrowed calling `closeTrove()` will succeed and owner's balance will get burned, making total
supply of accounting token 0.

## Liquity recovery mode
Users are not able to exit the Trove in case the Liquity system is in recovery mode (total CR < 150%).
This is because in recovery mode only pure collateral top-up or debt repayment is allowed.
This makes exit from this bridge impossible in recovery mode because such exit is always a combination of debt
repayment and collateral withdrawal.

## How can the accounting of the bridge be impacted by interactions performed by other parties than the bridge?
These are the outside influences which can affect the bridge:
1. ETH price movement,
2. Trove redemption,
3. debt redistribution,
4. liquidity in the LUSD/USDC and USDC/ETH 500 bps fee tier pools.

## Is this contract upgradable?
No

## Does this bridge maintain state? If so, what is stored and why?
Yes, the bridge itself is an ERC20 token and the bridge token balances are used for accounting.