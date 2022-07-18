# Spec for Yearn Bridge

## What does the bridge do? Why build it?

The bridge deposits some underlying token to it's compatible Yearn Vault, receiving `yvToken`, a staked underlying derivative that earns a yield from various strategies. We build it to allow users to earn yield on their tokens.

## What protocol(s) does the bridge interact with ?

Yearn Bridge interacts with various protocols to provide the necessary functionality. The protocols used depend on the underlying token as some strategies are not compatible with some tokens. Strategies, and thus protocols, may be added or removed at any time.  
The full list of strategies and protocols can be found [here](https://meta.yearn.finance/api/1/strategies/all) and [here](https://github.com/yearn/yearn-meta).

## What is the flow of the bridge?
Two main flows are used by the bridge, one for depositing tokens and one for withdrawing tokens.

### Deposit
When the bridge receives a deposit request, we are using the Yearn Lens Registry contract ([here](https://etherscan.io/address/0x50c1a2eA0a861A967D9d0FFE2AE4012c2E053804#readContract)) in order to get the most recent Vault for the supplying underlying Token.  
If the bridge receives `ETH` as the input token it will first wrap it to transform it to `wETH` as it is the expected ERC20 token for the `ETH` vaults at Yearn.  

Then, after some checks, we will deposit the supplied token to the vault and receive a number of shares matching our deposited amount.

The gas cost for ERC20 deposit is ~230k.
The gas cost for ETH deposit is ~118k.

### Withdrawal
When the bridge receives a withdrawal request with a yvToken as `inputAssetA`, we will simply withdraw the supplied share amount of yvToken from the vault. Based on the difference of PricePerShare between the deposit and withdrawal, the amount of underlying token received should be increased.
If the supplied `outputAssetA` is `eth` we will unwrap the underlying `wETH` token received to `ETH` native token before sending them to the `ROLLUP_PROCESSOR` for the given `interactionNonce`.

The gas cost for ERC20 withdrawal is ~225k.
The gas cost for ETH withdrawal is ~238k.


### General Properties for both deposit and withdrawal

- The bridge is synchronous, and will always return `isAsync = false`.

- The bridge uses `auxData` where `0` means `deposit` and `1` means `withdrawal`.

- The Bridge perform token pre-approvals in the constructor to allow the all the required tokens to work correctly on the approval side. A function to approve a specific vault also exists for new Vaults. It is safe to do, as the bridge is not holding funds itself.

## Can tokens balances be impacted by external parties, if yes, how?
The amount of shares received from the vault is not affected by external parties.
However depending on the success or failure of the strategies, the Price Per Share of the vault may be impacted, increasing the amount of underlying token received on withdrawal if the strategies are successful, but decreasing it if the strategies are unsuccessful.

## Is the contract upgradeable?

No, the bridge is immutable without any admin role.

## Does the bridge maintain state?

No, the bridge don't maintain a state.
