# Aztec Connect Bridges Specification Template

## What does this bridge do? Why did you build it?

The bridge allows people to do a "group-withdraw" that essentially can be seen as donations to an address on L1, from a group of people within Aztec.

## What protocol(s) does the bridge interact with?

The bridge only interacts with the ERC20 tokens that it are to transfer

## What is the flow of the bridge?

The bridge only support one flow, namely sending funds to the specified address. The bridge has an internal mapping of `id`s to addresses, and use the `auxData` to specify the id.

## Please list any edge cases that may restrict the usefulness of the bridge or that the bridge prevents explicit.

The bridge are forwarding 30K gas to the receipient receive function if transferring eth, so if that is insufficient, it will revert.

## How can the accounting of the bridge be impacted by interactions performed by other parties than the bridge? Example, if borrowing, how does it handle liquidations etc.

The bridge can only be impacted by other parties, if a donation is made to a unlisted id.
If this is the case, someone can list donees until they hit the id and get the donation themselves.

## What functions are available in [/src/client](./client)?

While there is a client class, it is of little use, as the bridge newer expects to receive anything back.

## Is this contract upgradable? If so, what are the restrictions on upgradability?

The contract is immutable and have no admin controls at all.

## Does this bridge maintain state? If so, what is stored and why?

The bridge maintain a append-only mapping of donees.
The mapping is used to allow passing the receipient through the auxdata (64 bits).
