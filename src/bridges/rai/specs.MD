# RaiBridge

The contract takes native ETH or WETH as collateral and ouputs RAI. You can then repay the RAI and get the locked ETH/WETH collateral back.
Including the RAI the contract also outputs RaiBridge ERC20 tokens (in the same amount as the RAI) to keep track of the respective depositors in that particular RaiBridge contract. So on repayment of RAI please also deposit the Bridge ERC20 tokens as "inputAssetB" else the contract wont accept your RAI.

### Constructor()

On contract deployment pass the rollUpProcessor address & "name", "symbol" of the Bridge ERC20 token.

### Depositing ETH/WETH borrowing RAI

After the contract deployment, the first step is to initialize the RAI safe with some ETH and a <strong>collateral ratio</strong>. For further deposits after that, the contract will follow this initialized collateral ratio.

To initialize, call the convert() method, with the collateral ratio in the "auxData" param &

```
inputAssetA: ETH/WETH
inputAssetB: empty
outputAssetA: RAI
outputAssetB: Bridge ERC20 tokens
totalInputValue: Total ETH/WETH
auxData: Collateral Raio in BPS, 20000=200% (divided by 10000)
```

Also, at initialization (which must be done by the Aztec Team most probably) you must supply enough ETH/WETH to borrow atleast 1469 RAI else the method will revert. (This is a condition in the RAI smart contracts)

Once initialization is done, there are no further conditions of minimum 1469 RAI borrowing. Call the convert method with any amount of ETH/WETh to borrow RAI. Also keep the auxData param 0 after that, because the contract will track the collateral ratio of the RAI safe and output you ETH based on that collateral ratio.

To check the collateralRatio and other data of the contract, you can call the <strong>getSafeData()</strong> view method. It will output the following

```
collateralRatio: the current collateralRatio of the contract in BPS (20000 => 200%)

raiToEth: Ratio of Rai to ETH

safe: This will output two values -> (Total locked WETH in the contract, Total RAI borrowed)
```

### Repaying RAI & withdrawing ETH/WETH back

To repay RAI call the convert method with

```
inputAssetA : RAI
inputAssetB: Bridge ERC20 tokens
outputAssetA: ETH/WETH
outputAssetB: empty
```

This will burn your BridgeERC20 tokens, repay the RAI and output you the ETH/WETH based on the current collateral ratio.

The amount of Bridge ERC20 tokens must be equal to the amount of RAI.

### Notes

1. In case of ETH deposit or withdrawals: The RAI contracts only take WETH, so in case of ETH deposits, it is first converted to WETH using the WETH contract and then deposited into the RAI safe. Vice versa for withdrawals.

2. \_addCollateral() internal method: This method contains all the logic for depositing with the RAI contracts.

3. \_removeCollateral() internal method: This method contains all the logic for repayment with the RAI contracts.

4. priceFeed: Chainlink price feed is being used to get the rai to ETH ratio (used for the collateral ratio calculation & also for calculating the expected RAI to be borrowed based on the current collateral ratio)

5. The RAI safes have a liquidation RATIO of 145%.
