#!/bin/sh

# Output the lister and deployer addresses
# The anvil deployer address for the mainnet fork
LISTER_ADDRESS="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"

# Output deployed artifacts addresses (requested fro the contracts container running @ CONTRACTS_HOST)
ADDRESSES=(
    ROLLUP_CONTRACT_ADDRESS
    FAUCET_CONTRACT_ADDRESS
    PERMIT_HELPER_CONTRACT_ADDRESS
    FEE_DISTRIBUTOR_ADDRESS
    BRIDGE_DATA_PROVIDER_CONTRACT_ADDRESS
)

# Wait for host
CONTRACTS_HOST=${CONTRACTS_HOST:-"http://localhost:8547"}
echo "Waiting for contracts host at $CONTRACTS_HOST..."
while ! curl -s $CONTRACTS_HOST > /dev/null; do sleep 1; done;

# Export keys to env variables
for ADDRESS in $ADDRESSES; do
    VALUE=$(curl -s $CONTRACTS_HOST | jq -r .$ADDRESS)
    echo "$ADDRESS=$VALUE"
    export $ADDRESS=$VALUE
done
export ROLLUP_PROCESSOR_ADDRESS=$ROLLUP_CONTRACT_ADDRESS