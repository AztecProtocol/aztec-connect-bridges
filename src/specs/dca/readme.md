# Dollar Cost Averaging Bridge

## What does the bridge do? Why did you build it?
The bridge allows a user to enter a DCA (Dollar Cost Average) position, selling one asset and buying another over a period of time. 

## What protocol(s) does the bridge interact with?
Strictly speaking, the bridge implements a DCA protocol itself and has the ability to operate given only a pricing oracle (Chainlink). However, this requires external parties to trade with the bridge, so an alternative using Uniswap V3 is also outlined. 

- [ChainLink](https://chain.link/)
- [Uniswap V3](https://uniswap.org/)

## What is the flow of the bridge?

The bridge is asynchronous and primarily have one flow from inside the Aztec Connect rollup, the deposit. However, it allows a number of operations to be executed directly from layer 1. 

### Deposit

   - What actions does this bridge make possible?
   - Are all bridge interactions synchronous, or is the a asynchronous flow?
   - For each interaction define:
     - All input tokens, including [AztecType](https://github.com/AztecProtocol/aztec-connect-bridges/blob/master/src/aztec/libraries/AztecTypes.sol) info
     - All output tokens, including [AztecType](https://github.com/AztecProtocol/aztec-connect-bridges/blob/master/src/aztec/libraries/AztecTypes.sol) info
     - All relevant bridge address ids (may fill in after deployment)
     - use of auxData
     - gas usage
     - cases that that would make the interaction revert (low liquidity etc)
   - Please include any diagrams that would be helpful to understand asset flow.

4. Please list any edge cases that may restrict the usefulness of the bridge or that the bridge prevents explicit.

5. How can the accounting of the bridge be impacted by interactions performed by other parties than the bridge? Example, if borrowing, how does it handle liquidations etc.

6. What functions are available in [/src/client](./client)?

   - How should they be used?

7. Is this contract upgradable? If so, what are the restrictions on upgradability?

8. Does this bridge maintain state? If so, what is stored and why?

9. Any other relevant information
