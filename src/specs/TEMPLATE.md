# Aztec Connect Bridges Specification Template

_Help the Aztec community make Aztec Connect easier to build on and interact with by documenting your work.
This spec template is meant to help you provide all of the information that a developer needs to work with your bridge.
Complete specifications will be linked in the official Aztec docs at https://docs.aztec.network._

You can view an example spec [here](#add-link).

1. What does this bridge do? Why did you build it?
2. What protocol(s) does the bridge interact with?

   - Include links to website, github, etherscan, etc
   - Include a small description of the protocol(s)

3. What is the flow of the bridge?

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
