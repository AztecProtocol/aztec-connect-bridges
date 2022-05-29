# Flows

## Deposit to Theta ETH Vault (Ribbon v2)

1. Check that input asset is WETH and output asset is ZKRBNTokens. If it is, proceed into deposit case.
2. Convert `totalInputValue` to WETH denomination-normalized amount and store value in `wethNormalizedTotalInputAmount`.
3. Get `numUnredeemedSharesBeforeDeposit` from [RibbonThetaVault ETH Call](https://etherscan.io/address/0x0FABaF48Bbf864a3947bdd0Ba9d764791a60467A).
4. Deposit `wethNormalizedTotalInputAmount` into RibbonThetaVault ETH Call.
5. Get `numUndreemedSharesAfterDeposit` from RibbonThetaVault ETH Call.
6. Get `numUnredeemedSharesAfterDeposit - numUnredeemedSharesBeforeDeposit` and store into `numUnredeemedSharesCreated`.
7. Mint `numUnredeemedSharesCreated` zkRThetaVaultTokens.

## Withdraw from Theta ETH Vault (Ribbon v2)

1. Check that input asset is 
