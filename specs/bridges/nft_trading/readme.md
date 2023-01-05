# Spec for NFT Trading Bridge

## What does the bridge do? Why build it?

This bridge enables user to  trading their NFT on the established Layer 1 NFT marketplaces, aka [OpenSea](https://opensea.io/), where users can list and purchase NFTs from Aztec L2 without revealing their L1 identities.
In this way, the owner of one NFT owner is in private with the power of Aztec's zero knowledge rollup. So this bridge can enhance the secret characterist of Layer 1 user.


## What protocol(s) does the bridge interact with ?


The bridge interacts with [OpenSea](https://opensea.io/).

## What is the flow of the bridge?
The simple flow as below:
1. User A on Aztec chain bridge interface pay and buy an NFT on Opensea in Ethereum.
2. The "Buy" order and relevant fee is send to L1 by Aztec's rollup.
3. The bridge contract in L1 is triggered to interact with OpenSea protocol.
4. Then the bridge contract own this NFT and record it to a private user id.
5. The User A On Aztec can redeem this NFT anytime, with his valid signature. 



### General Properties of convert(...) function

- The bridge is synchronous, and will always return `isAsync = false`.

- The bridge uses `_auxData` to encode the target NFT, id, price.

- The Bridge perform token pre-approvals to allow the `ROLLUP_PROCESSOR` and `UNI_ROUTER` to pull tokens from it.
  This is to reduce gas-overhead when performing the actions. It is safe to do, as the bridge is not holding the funds itself.

## Is the contract upgradeable?

No, the bridge is immutable without any admin role.

## Does the bridge maintain state?

No, the bridge doesn't maintain a state.
However, it keeps an insignificant amount of tokens (dust) in the bridge to reduce gas-costs of future transactions (in case the DUST was sent to the bridge).
By having a dust, we don't need to do a `sstore` from `0` to `non-zero`.

## Does this bridge maintain state? If so, what is stored and why?

Yes, this bridge maintain the NFT bought from NFT to relevant user's private identity. 
This state is a record for user to redeem their NFT asset.