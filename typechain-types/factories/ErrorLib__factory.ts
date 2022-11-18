/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import { Signer, utils, Contract, ContractFactory, Overrides } from "ethers";
import type { Provider, TransactionRequest } from "@ethersproject/providers";
import type { PromiseOrValue } from "../common.js";
import type { ErrorLib, ErrorLibInterface } from "../ErrorLib.js";

const _abi = [
  {
    inputs: [
      {
        internalType: "address",
        name: "token",
        type: "address",
      },
    ],
    name: "ApproveFailed",
    type: "error",
  },
  {
    inputs: [],
    name: "AsyncDisabled",
    type: "error",
  },
  {
    inputs: [],
    name: "InvalidAuxData",
    type: "error",
  },
  {
    inputs: [],
    name: "InvalidCaller",
    type: "error",
  },
  {
    inputs: [],
    name: "InvalidInput",
    type: "error",
  },
  {
    inputs: [],
    name: "InvalidInputA",
    type: "error",
  },
  {
    inputs: [],
    name: "InvalidInputAmount",
    type: "error",
  },
  {
    inputs: [],
    name: "InvalidInputB",
    type: "error",
  },
  {
    inputs: [],
    name: "InvalidNonce",
    type: "error",
  },
  {
    inputs: [],
    name: "InvalidOutputA",
    type: "error",
  },
  {
    inputs: [],
    name: "InvalidOutputB",
    type: "error",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "token",
        type: "address",
      },
    ],
    name: "TransferFailed",
    type: "error",
  },
];

const _bytecode =
  "0x60566037600b82828239805160001a607314602a57634e487b7160e01b600052600060045260246000fd5b30600052607381538281f3fe73000000000000000000000000000000000000000030146080604052600080fdfea264697066735822122041156a4d5889b22f70e743badb33deb26a9c3d29b4e679cc129e0cc09c7f9d8b64736f6c634300080a0033";

type ErrorLibConstructorParams =
  | [signer?: Signer]
  | ConstructorParameters<typeof ContractFactory>;

const isSuperArgs = (
  xs: ErrorLibConstructorParams
): xs is ConstructorParameters<typeof ContractFactory> => xs.length > 1;

export class ErrorLib__factory extends ContractFactory {
  constructor(...args: ErrorLibConstructorParams) {
    if (isSuperArgs(args)) {
      super(...args);
    } else {
      super(_abi, _bytecode, args[0]);
    }
  }

  override deploy(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<ErrorLib> {
    return super.deploy(overrides || {}) as Promise<ErrorLib>;
  }
  override getDeployTransaction(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): TransactionRequest {
    return super.getDeployTransaction(overrides || {});
  }
  override attach(address: string): ErrorLib {
    return super.attach(address) as ErrorLib;
  }
  override connect(signer: Signer): ErrorLib__factory {
    return super.connect(signer) as ErrorLib__factory;
  }

  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): ErrorLibInterface {
    return new utils.Interface(_abi) as ErrorLibInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): ErrorLib {
    return new Contract(address, _abi, signerOrProvider) as ErrorLib;
  }
}