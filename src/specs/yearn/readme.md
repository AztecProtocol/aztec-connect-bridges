# Spec for Yearn Bridge

## What does the bridge do? Why build it?

The bridge deposits an ERC20 token into the corresponding Yearn Vault, and receives another ERC20 called yvToken that represents its deposit in the vault. 
The tokens deposited into the vault are going to be invested using different strategies, with different capital allocations based on risk and profitability.
This will accrue yield and will reflect it increasing the `pricePerShare` of the yvToken.

## What protocol(s) does the bridge interact with ?

The bridge interacts will only interact with Yearn Vaults.

## What is the flow of the bridge?
Users will use the bridge in two cases: deposit and withdraw.

### Deposit
When the bridge receives a deposit request, we use Yearn Lens Registry contract ([here](https://etherscan.io/address/0x50c1a2eA0a861A967D9d0FFE2AE4012c2E053804#readContract)) to get the most recent Vault for the token to be deposited.

If the bridge receives `ETH` as the input token it will first wrap into `WETH` and then follow the same flow as any other ERC20.

We check that `auxData` is correct (`0`), `inputValue` is greater that 0 and that the token is an ERC20. After that, the bridge calls the `deposit` function to send the tokens to the vault and receive yvTokens as a receipt for it.

The gas cost for ERC20 deposit is ~230k.
The gas cost for ETH deposit is ~118k.

### Withdrawal
When the bridge receives a withdrawal request with a yvToken as `inputAssetA`, the bridge calls the `withdraw` function of the contract. This will burn the yvTokens and send back the principal plus the yield accrued. The amount of underlying to be received is equal to the amount of yvTokens times `pricePerShare`.

If the supplied `outputAssetA` is `ETH`, we follow the same flow as any other ERC20, and at the end we unwrap `WETH` into `ETH` before sending them to the `ROLLUP_PROCESSOR` for the given `interactionNonce`.

The gas cost for ERC20 withdrawal is ~225k.
The gas cost for ETH withdrawal is ~238k.


### General Properties for both deposit and withdrawal

- The bridge is synchronous, and will always return `isAsync = false`.

- The bridge uses `auxData` where `0` means `deposit` and `1` means `withdrawal`.

- The bridge performs infinite token approvals in the constructor to allow all the required tokens. There's also a function to approve a specific Vault to handle new deployments. Infinite approvals are safe because the bridge doesn't hold any funds.

## Can tokens balances be impacted by external parties, if yes, how?
The number of shares received from the vault is not affected by any external party.

On withdrawal, the number of tokens received will depend on the `pricePerShare`, which is usually higher than when the user deposited. 

## Is the contract upgradeable?

No, the bridge is immutable without any admin role.

## Does the bridge maintain state?

No, the bridge doesn't maintain a state.
