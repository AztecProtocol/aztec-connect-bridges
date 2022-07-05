# Uniswap V3 Bridge for Liquidity Provision : List of weird changes that are worth noting

Bug / change # 1 : 

    In order to integrate the use of several uniswap libraries into the bridges, changes had to be made to the libraries contents 
so that they could compile successfully with solidity 0.8.10. This was because solidity 0.8.x introduced some compilation-breaking
changes like preventing non-explicit type conversions. So in order to ensure compilation, in these libraries, whenever there was
a non-explicit type conversion, I made it explicit. e.g. a conversion like address(uint256(number)) becomes address(uint160(uint256(number))), so that compilation succeeds. 
See 
https://docs.soliditylang.org/en/v0.8.11/080-breaking-changes.html
for the breaking changes. The files modified are FullMath.sol, and PoolAddress.sol and TickBitmap.sol.

Bug / change # 2 

Changes to hardhat config. For some reason, hardhat/typechain cannot compile when the hardhat config looks like below:

solidity: {
    compilers: [
      {
        version: '0.8.10',
      },
    ],
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },

But when I change the solidity version to be 0.8.10 and get rid of the explicit instruction to have the compiler be 0.8.10, 
everything compiles fine. See below. Above hardhat config fails, below succeeds. 
solidity: {
    version: "0.8.10",
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },