# Subsidy

## What does it do?

See documentation in the [contract file](../../../aztec/Subsidy.sol).

## Usage

One way to fund a subsidy is through Etherscan:

1. Go to the contract's `subsidize(...)` function on [Etherscan](https://etherscan.io/address/0xabc30e831b5cc173a9ed5941714a7845c909e7fa#writeContract#F5)
2. Connect your wallet.
3. Fill in the following details:

- **payableAmount** – This is the amount of ETH you want to commit to the subsidy, in Wei.
  We recommend initially setting this value relatively low (somewhere between 20-40% of the total grant size) because it’s possible we will want to change the Subsidy parameters later on,
  and it is not possible to do that before current subsidy runs out. The minimum acceptable value is set to 0.1 ETH.

- **\_bridge** – This is the address of the bridge you are subsidizing.
- **\_criteria** – This is the parameter specifying which flow you want to subsidize.
  Definition of this parameter is bridge specific and can for example distinguish between deposit or withdrawal flows (see the [Yearn bridge](../../../bridges/yearn/YearnBridge.sol)) or a specific combination of input/output assets (see [Uniswap bridge](../../../bridges/uniswap/UniswapBridge.sol)).
- **\_gasPerMinute** – This is the parameter for declaring how much gas per minute you are willing to subsidize.
  This value defines the rate at which the subsidy is released.
  The minimum acceptable value is bridge specific.
  We usually set **\_gasPerMinute** value such that a call is fully subsidized once per day.
  Fully subsidized would mean that the user’s base fee would get covered in full, and users would only have to pay priority fee tips

5.  Send the transaction by clicking “Write”.

> Note: This is a standard contract interaction so feel free to fund the subsidy any other way.
> If you are using a multi-sig, you can instead propose this transaction in the UI of the multi-sig wallet, with the same parameters.
