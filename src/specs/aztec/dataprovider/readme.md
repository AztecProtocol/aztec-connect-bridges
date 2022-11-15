# DataProvider contract

## What does it do?

It is a contract we use as a source of truth when it comes to configuration of bridges and assets.
It is mainly used by our frontend to get a bridge or asset information by a tag.

## Usage

Before running the commands bellow export relevant environment variables:

```bash
export RPC="https://mainnet.infura.io/v3/737bcb5393b146d7870be2f68a7cea9c" && PRIV_KEY="PROVIDER_OWNER_PRIVATE_KEY"
```

### Adding a bridge

```bash
cast send 0xB4319947947781FFe91dDf96A32aF2D4693FEf64 "addBridge(uint256,string)" "2" "ExampleBridge" --rpc-url $RPC --private-key $PRIV_KEY
```

### Adding an asset

```bash
cast send 0xB4319947947781FFe91dDf96A32aF2D4693FEf64 "addAsset(uint256,string)" "2" "wsteth" --rpc-url $RPC --private-key $PRIV_KEY
```

### Adding multiple assets and bridges

```bash
cast send 0xB4319947947781FFe91dDf96A32aF2D4693FEf64 "addAssetsAndBridges(uint256[],string[],uint256[],string[])" '[2,1]' '["wsteth","dai"]' '[5,8]' '["ExampleBridge_deposit","ExampleBridge_withdraw"]' --rpc-url $RPC --private-key $PRIV_KEY
```
