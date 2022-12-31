# how to run this

1. create an .env file
```
PRIVATE_KEY=0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
network=mainnet
simulateAdmin=false
```
2. start anvil
```
anvil --fork-url https://mainnet.infura.io/v3/${API_KEY}
```
3. run this command
```
forge script src/gas/nft-basic/NftVaultGas.s.sol --fork-url http://localhost:8545 --sig "measure()" --private-key 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80 -vvvv
```