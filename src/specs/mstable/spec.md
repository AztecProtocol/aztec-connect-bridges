# Supported Assets

The mStable bridge provides support from bridging DAI to imUSD and imUSD back to DAI on the Ethereum network.

# Flows

The bridge can only be accessed with any bridging functionality through the `convert` method.

If the bridge's `convert` method is supplied DAI on Ethereum, it will return the caller with the best priced amount of imUSD via mStable smart contracts.

If the bridge's `convert` method is is supplied imUSD on Ethereum, it will return the caller with the best priced amount of DAI via mStable smart contracts.
