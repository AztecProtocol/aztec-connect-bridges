# Index Bridge Spec

## Flow

The IndexBridge contract allows users to buy/issue icETH with ETH and to sell/redeem icETH for ETH. Below you can the supported flows and the required inputs for a desired flow and resulting output. 

|                           | Issue icETH | Buy ETH (0.3% pool) | Buy ETH (0.05% pool) | Redeem icETH | Sell ETH (0.3% pool) | Sell ETH (0.05% pool) | 
|---------------------------|-------------|---------------------|----------------------|--------------|----------------------|-----------------------|
| inputAssetA               | ETH         | ETH                 | ETH                  | icETH        | icETH                | icETH                 |  
| inputAssetB               | empty       | empty               | empty                | empty        | empty                | empty                 | 
| outputAssetA              | icETH       | icETH               | icETH                | eth          | eth                  | eth                   | 
| outputAssetB              | ETH         | empty               | empty                | empty        | empty                | empty                 | 
| flowSelector (in auxData) | 1           | 3                   | 5                    | 1            | 3                    | 5                     |       |
|                           |             |                     |                      |              |                      |                       |      |
| outputValueA (type)       | icETH       | icETH               | icETH                | ETH          | ETH                  | ETH                   |     |
| outputValueB (type)      |   ETH         | empty               | empty                | empty        | empty                | empty                 |     
  

## Encoding and Sanity checks

There are two sanity checks passed into the contract through the auxData variable. One is the maxSlip parameter that specifies an acceptable slip in terms of percent (in 4 decimals) of the expected return based on Oracle prices and the cost of creating a leverage position. E.g. setting maxSlip to 9999 means that we require a minium of 0.9999%*expetedReturn to be returned. 

The second sanity check is of the Oracle prices, oracleLimit. It is the price of ETH/stETH when issuing/redeeming or the price of ETH/icETH when buying/selling. It is used either as an upper limit when buying/issuing or as a lower limit when selling/redeeming. It is given in 4 decimals. E.g. setting oracleLimit to 9950 when issuing icETH requires the oracle price of ETH/stETH from Chainlink to be below 0.9950, setting it to 9000 when selling requires the univ3 TWAP price of ETH/icETH to be above 0.9000.

MaxSlip is encoded into the first 16 bits, oracleLimit in the next 16 bits and flowSelector in the final 32 bits of the uint64 auxData variable.
