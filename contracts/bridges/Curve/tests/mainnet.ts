export const CURVE_ADDRESS_PROVIDER =
  "0x0000000022D53366457F9d5E68Ec105046FC4383";

interface TokenInfo {
  address: string,
  holder: string,
}

export const tokens: {[name: string]: TokenInfo} = {
  USDC: { address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", holder: "0x72a53cdbbcc1b9efa39c834a540550e23463aacb"},
  DAI: { address: "0x6b175474e89094c44da98b954eedeac495271d0f", holder: "0x72a53cdbbcc1b9efa39c834a540550e23463aacb"},
  USDT: { address: "0xdac17f958d2ee523a2206206994597c13d831ec7", holder: "0xf7b2f3cd946052f8b397f801299b80f053515af9"},
  WETH: { address: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2", holder: "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"},
  WBTC: { address: "0x2260fac5e5542a773aa44fbcfedf7c193bc2c599", holder: "0x176f3dab24a159341c0509bb36b833e7fdd0a132"},
  UST: { address: "0xa47c8bf37f92abed4a126bda807a7b7498661acd", holder: "0x738cf6903e6c4e699d1c2dd9ab8b67fcdb3121ea"},
};
