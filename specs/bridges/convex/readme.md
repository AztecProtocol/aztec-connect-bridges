# Spec for Convex Staking Bridge

## What does the bridge do? Why build it?

The bridge stakes Curve LP tokens via Convex Finance. Convex Finance Booster stakes Curve LP tokens provided by the user and mints its own pool specific Convex LP tokens for the user to keep track of the staked Curve LP tokens and the earned rewards.

The advantage of staking on Convex Finance over Curve Finance is that the user earns boosted CRV rewards right away and can withdraw the staked tokens any time. On top of this, the user earns CVX (Convex tokens) and at some pools even additional rewards.

## What protocol(s) does the bridge interact with ?

The bridge interacts with two protocols. Primarily with Convex Finance that operates with the given Curve LP tokens on Curve.

[Convex Finance](https://www.convexfinance.com/) is a protocol built on top of Curve to make yield farming much easier and to automatically get boosted rewards. Convex Finance allows staking of CRV tokens or Curve LP tokens on Curve Finance without the need to lock user's CRV away and the user can start earning boosted CRV right away. This bridge only works for staking of Curve LP tokens.
Note: Convex Finance has its own governance token CVX which user earns as part of staking.

[Curve](https://curve.fi/) is a AMM that specializes in pools with low internal volatility (stableswap). Curve Finance provides us with many LPs to which a user may provide liquidity and earn rewards. Rewards are paid out in tokens specific to the LP and/or pool specific `Curve LP tokens`. To be able to utilize the full potential of the earned LP tokens, it is necessary to stake them. Here comes in play Convex Finance.

## What is the flow of the bridge?

There are two flows of Convex staking bridge, namely deposits and withdrawals. It is necessary to mention that both flows work with pool specific Representing Convex Token (RCT) that is deployed for each pool on its loading.
Interesting fact is that both flows work with different number of assets. Deposit work with a single input asset and a single outputAsset while Withdraw works with a single input asset and two output assets.

![Asset flow diagram](./ConvexStakingBridge.svg)

### Deposit (Stake)

TL;DR: Bridge stakes Curve LP tokens into Curve pool liquidity gauge contract via Convex Finance Booster. Subsequently new Convex LP tokens of the corresponding pool are minted in 1:1 ratio and transferred to crvRewards contract. Bridge mints pool specific RCT token to match the balance of minted Convex LP token. RCT tokens are recoved by Rollup Processor.

Before user starts with the deposit, it is necessary to ensure that the pool for the given assets has already been loaded.

Bridge expects Curve LP token on input and RCT token on output in order to perform deposit. Curve LP tokens are transferred from Rollup Processor to the bridge. Bridge checks if the provided RCT token has been already deployed and whether it was deployed for the same pool as the provided Curve LP token. If these conditions are met, deposit may proceed. Bridge finds the correct pool that corresponds to the Curve LP token on input. Convex Finance has a Booster contract that operates across all the pools. Booster handles the complete deposit (staking) process and is approved to manage bridge's Curve LP tokens. First, it transfers the Curve LP tokens into Staker contract that then stakes them to Liquidity Gauge of the specific pool. New Convex LP tokens are minted, representing the staked LP tokens in Convex Finance in 1:1 ratio. Convex LP tokens are transferred to Convex crvRewards contract. CrvRewards is now in possession of the minted Convex LP tokens and through them keeps track of the staked Curve LP tokens for the bridge (or any other staking user). RCT tokens are minted by the bridge and its balance reflects the amount of the minted Convex LP tokens. Eventually, the minted RCT tokens are recover by the Rollup Processor.

RCT exists to enable Rollup Processor to properly perform deposits and withdrawals for different users at different times. Rollup Processor expects to work with at least one input and one output asset and both assets need to be able to be owned by it. Because minted Convex LP tokens are only indirectly owned by the bridge and the actual ownership is given to crvRewards contract, Convex LP token cannot be transferred back to the Rollup Provider. RCT tokens represents the minted Convex LP tokens, but this time the token is fully owned by the bridge and can be transferred elsewhere.

Gas cost of a deposit varies based on the pool. Costs mostly fluctuate in range 750k to 950k. This does not include the transfers to/from the Rollup Processor.

**Edge cases**:

- If pool is not loaded, deposit to this pool will fail
- Convex Finance has to support the Curve LP token user is trying to stake. If no pool matches the provided Curve LP token, no staking will happen.
- Staking amount cannot be zero.
- Pool can be shut down and no staking will happen

### Withdrawal (Unstake)

TL;DR: Rollup Processor transfers RCT tokens to the bridge. Bridge withdraws staked Curve LP tokens and staking rewards via Booster and direct interaction with crvRewards contract. Earned rewards are swapped for ether. Booster burns Convex LP tokens and returns staked Curve LP tokens to the bridge. RCT tokens are burned, returned Curve LP tokens and bridge (ether) balance are recovered by Rollup Processor.

Before user starts with withdrawal, it is necessary to ensure that the pool for the given assets has already been loaded.

Bridge expects a single input asset - RCT token - and two output assets - Curve LP token and ETH asset - to perform withdrawal. Rollup Processor transfers RCT tokens to the bridge. Then a check is performed whether the pool for the given assets has already been loaded and the RCT token has already been deployed. Next check assures that the input and output tokens belongs to the same pool and the second output asset represents ether. If both checks pass, the bridge searches for the right pool and then continues with withdrawal of Curve LP tokens. Withdrawal process consists of three steps. First, the bridge calls crvRewards contract to transfer the Convex LP tokens to the bridge and claim rewards. Second, the earned rewards tokens - CRV and CVX - are swapped for ether if the earned amount allows it. Third, the bridge calls the Booster to withdraw the deposited Curve LP tokens. It starts by burning the Convex LP tokens, then retrieves Curve LP tokens from Staker contract. If sufficient funds are not available, Staker pulls more deposited Curve LP tokens from the specific Curve pool liquidity gauge contract. Desired amount of Curve LP tokens is then retrieved and transferred back to the bridge. RCT tokens are burned to equally match the new amount of Convex LP tokens. Finally, Rollup Processor recovers the Curve LP tokens and ether.

Claimed rewards are the boosted CRV tokens, CVX tokens and for some pools some additional rewards. The most notable reward tokens - CRV and CVX - are swapped for ether and send to the Rollup Processor if the amount is high enough or if slippage is higher than 1 %. Minimum amount required for the conversion to happen is given by the immediate conversion rate. If rewards cannot be claimed, the rewarded tokens are still owned by the bridge until the point when on withdrawal the token balances are sufficiently high enough to be swapped. Other additional rewards are, for their insignificance, not claimed.

Exchange of tokens for ether takes place in Curve's pools. 
Swap          |  Curve Pool  |  Link to Pool
CRV => ether  |  crveth      |  https://curve.fi/#/ethereum/pools/crveth/swap
CVX => ether  |  cvxeth      |  https://curve.fi/#/ethereum/pools/cvxeth/swap

Gas cost of a withdrawal varies based on the pool. Withdrawal costs about 1.4M when claimed rewards are not swapped and about 2.1M when they are. Swap costs about 650K. Costs include claim of subsidy but do not include the transfers to/from the Rollup Processor.

**Edge cases**

- If pool is not loaded, withdrawal from this pool will fail.
- Withdrawal impossible without staking tokens into the pool first.
- Withdrawal amount has to match amount of tokens staked under the interaction.
- Withdrawal amount cannot be zero.
- OutputAssetB (ether) will not return any ether unless the collected amount of reward tokens is high enough for an exchange. 

### General Properties for both deposit and withdrawal

- The bridge is synchronous, and will always return `isAsync = false`.
- The bridge does not use `auxData`.
- Bridge is stateless.

## Can tokens balances be impacted by external parties, if yes, how?

- Either a single pool or all pools at the same time can be shut down. This can impact the balances of certain contracts where the tokens typically are, however, do not result in any tokens lost.

- A single pool can be shut down by Booster's Pool Manager contract (0x5F47010F230cE1568BeA53a06eBAF528D05c5c1B)
  Any interaction with a pool supported by Convex Finance can be shut down by Convex pool manager contract.
  Pool shutdown will force all tokens from Staker and Gauge contracts to be transferred to Booster. Withdrawals will no get impaired.
  Only the Staker's and Gauge's balances (including your share) are displaced.
  Note: Deposit will not be possible.

- All pools can be single handedly shut down by Booster's Owner contract (0x3cE6408F923326f81A7D7929952947748180f1E6)
  Does and allows exactly the same thing as shut down of a single pool described above, only for all the pools.

## Is the contract upgradeable?

No, the bridge is immutable without any admin role.

## Does the bridge maintain state?

No, the bridge does not maintain state.
