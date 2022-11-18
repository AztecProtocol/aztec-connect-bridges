/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import {
  Signer,
  utils,
  Contract,
  ContractFactory,
  BigNumberish,
  Overrides,
} from "ethers";
import type { Provider, TransactionRequest } from "@ethersproject/providers";
import type { PromiseOrValue } from "../common.js";
import type { MockPriceFeed, MockPriceFeedInterface } from "../MockPriceFeed.js";

const _abi = [
  {
    inputs: [
      {
        internalType: "uint256",
        name: "_price",
        type: "uint256",
      },
    ],
    stateMutability: "nonpayable",
    type: "constructor",
  },
  {
    inputs: [],
    name: "fetchPrice",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [],
    name: "lastGoodPrice",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
];

const _bytecode =
  "0x60a060405234801561001057600080fd5b5060405161013838038061013883398101604081905261002f91610037565b608052610050565b60006020828403121561004957600080fd5b5051919050565b60805160ca61006e60003960008181603b01526071015260ca6000f3fe6080604052348015600f57600080fd5b506004361060325760003560e01c80630490be831460375780630fdb11cf14606f575b600080fd5b605d7f000000000000000000000000000000000000000000000000000000000000000081565b60405190815260200160405180910390f35b7f0000000000000000000000000000000000000000000000000000000000000000605d56fea26469706673582212202f70fdaf76a1b40d842d9489cdaa5c206d34a4c82e05ce08304a6c88756e6d0a64736f6c634300080a0033";

type MockPriceFeedConstructorParams =
  | [signer?: Signer]
  | ConstructorParameters<typeof ContractFactory>;

const isSuperArgs = (
  xs: MockPriceFeedConstructorParams
): xs is ConstructorParameters<typeof ContractFactory> => xs.length > 1;

export class MockPriceFeed__factory extends ContractFactory {
  constructor(...args: MockPriceFeedConstructorParams) {
    if (isSuperArgs(args)) {
      super(...args);
    } else {
      super(_abi, _bytecode, args[0]);
    }
  }

  override deploy(
    _price: PromiseOrValue<BigNumberish>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<MockPriceFeed> {
    return super.deploy(_price, overrides || {}) as Promise<MockPriceFeed>;
  }
  override getDeployTransaction(
    _price: PromiseOrValue<BigNumberish>,
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): TransactionRequest {
    return super.getDeployTransaction(_price, overrides || {});
  }
  override attach(address: string): MockPriceFeed {
    return super.attach(address) as MockPriceFeed;
  }
  override connect(signer: Signer): MockPriceFeed__factory {
    return super.connect(signer) as MockPriceFeed__factory;
  }

  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): MockPriceFeedInterface {
    return new utils.Interface(_abi) as MockPriceFeedInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): MockPriceFeed {
    return new Contract(address, _abi, signerOrProvider) as MockPriceFeed;
  }
}