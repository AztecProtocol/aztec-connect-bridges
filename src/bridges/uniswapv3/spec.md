[![CircleCI](https://circleci.com/gh/AztecProtocol/aztec-connect-bridges/tree/master.svg?style=shield)](https://circleci.com/gh/AztecProtocol/aztec-connect-bridges/tree/master)

# Uniswap V3 Bridge for Liquidity Provision


These are the Aztec Connect bridges for Uniswap V3 Liquidity Provision. There is a main bridge, the SyncUniswapV3Bridge, and a 
secondary bridge, the AsyncUniswapV3Bridge. The main bridge handles standard LPing where two assets are provided, and an NFT representing the position is returned, while the secondary bridge is used for range orders. which is just LPing outside the current tick range. See : 
https://docs.uniswap.org/protocol/concepts/V3-overview/range-orders#:~:text=In%20typical%20order%20book%20markets,liquidity%20within%20a%20specific%20range.

The flows for the two bridges are presented as follows:

SyncUniswapV3Bridge :
There are 3 flows, the TwoPartMint interaction flow, the MintBySwap interaction flow, and the redemption flow.

TwoPartMint has two parts. This flow is intended for users who already have as zkAssets the assets for which they
intend to LP. E.g. zkDAI and zkETH are both held by the user and they want to LP for the DAI/ETH .3% pool. There exists a current limitation wherein only 1 real input asset can be provided to the bridge, per convert call. Hence we use two convert calls to process the interaction.

    1st convert call: 
    1 real input (zkDAI/DAI), 1 not used
    1 virtual output 1 not used

The real input is essentially deposited into the bridge, and a record (in the form of a struct called MintFunding) of the funding amount and the funding token's address is made in a data structure (a map ) called SyncMintFundingMap. Thus the funding which is used to fund the 2nd convert call is recorded. Ownership of this funding is proven through ownership of virtual notes, which prove ownership of an interaction nonce / specific interaction.

    2nd convert call:

    1 real input (zkETH/ETH) 1 virtual input
    1 virtual output 1 real output

On the 2nd convert call, based on the structure of the inputs/outputs, the bridge will understand the interaction to be the 2nd part of the TwoPartMint flow, and will use the virtual input to check for fundings made for TwoPartMint interactions, and use the assets deposited on the interaction for which the virtual input has ownership of

The bridge now has two assets which it can provide to a pool to LP, and the bridge will then call some internal functions which mostly amount to nonfungiblePositionManager.mint(...) being called. Once liquidity is minted, a record of this position's data is made in the form of a Deposit struct map. The position NFT is held by the bridge, and a virtual output is returned which the user can provide to redeem liquidity. 

The 1 real output is used for any refunds. 

MintBySwap is a flow where the user only has one asset but can indicate which pool they wish to LP for, and the bridge will swap half of their asset into the second asset of the pool, and then take the two assets and LP. 

    1 real (zkDAI/DAI) 1 not used
    1 virtual 1 real (zkETH/ETH)

The 1 real input (zkDAI/DAI) is used is as the first token/ swap input, and the  1 real output (zkETH/ETH) is used as the second token of the pool / swap output. After swapping, the bridge mints liquidity in the same pool (DAI/ETH) that it just swapped with. Any refunds are made to the 1 real output asset (superfluous amounts of refunded tokens are swapped to be the same token as the refund token). As in TwoPartMint, when liquidity is minted, a record of the position is made in the form of a Deposit struct mapping, and a virtual note output is returned , which proves ownership of the nonce/ deposit.

Redemption flow: 

    1 virtual input 1 not used
    1 real output 1 real output

The virtual input proves ownership of a position via the "deposits" mapping which is a uint256 -> Deposit struct mapping, where the uint256 is an interaction nonce. The virtual input's id , which is the nonce, is inputted, the bridge checks the mapping, and redeems liquidity based on the tokenId recorded in the Deposit struct. The assets returned correspond to the two real outputs.

AsyncUniswapV3Bridge: 
There are two flows: the minting/range order flow, and the redemption flow.

Minting/range order flow:

    1 real input 1 not used
    1 real output 1 real output

This interaction is asynchronous. 1 real input used the first token, 1 real output used as the second token for the pool. The 2nd real output is for the later finalise() call made by the rollupProcessor, so that the rollupProcessor can "allocate" an AztecAsset. Range orders only need 1 token to be funded, so the bridge will assume the output to have an amount of 0 when making the nonfungiblePositionManager.mint(...) call. When liquidity is minted, a record is made in the "deposits" uint256->Deposit struct mapping, just as in the synchronous bridge. However an additional record is made in an "asyncOrders" mapping which contains the expiry of the range order and whether it can be finalised. It can only be finalised if the current tick of the Uniswap pool drifts into limit price/range of the order or the order expires. If the order can be finalised, liquidity can be redeemed.

Redemption:
As explained, when the order is finalisable, liquidity can be redeemed. Redemption occurs through an external function called trigger() which takes a nonce as an arg and checks if the order corresponding to the nonce has had its limit range met. If it has , then it sets the finalisable bool var to true, and withdraws/burns liquidity. Then the caller may call rollupProcessor.processAsyncDeFiInteraction(...) to process the interaction and they will receive the outputs of the transaction. The interaction can also be finalised by calling cancel(uint256 interactionNonce) which will withdraw/burn liquidity of the position owned by the nonce if the order has expired, and then calling processAsyncDeFiInteraction as before. 

Other notes: 

These bridges requires user-defined data to function, via the uint64 auxData. For the synchronous bridge, this auxiliary data contains the tickLower and tickUpper of the LP, as well as the fee of the pool so it knows where to swap / mint liquidity in. The asynchronous bridge requires a tickLower, a tickUpper, a fee, as well as a number of days until expiry. 

The Uniswap.t.sol test contains good examples of how these flows actually look like in Solidity. 

