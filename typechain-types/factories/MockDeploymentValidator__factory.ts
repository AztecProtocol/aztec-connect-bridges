/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */
import { Signer, utils, Contract, ContractFactory, Overrides } from "ethers";
import type { Provider, TransactionRequest } from "@ethersproject/providers";
import type { PromiseOrValue } from "../common.js";
import type {
  MockDeploymentValidator,
  MockDeploymentValidatorInterface,
} from "../MockDeploymentValidator.js";

const _abi = [
  {
    inputs: [],
    stateMutability: "nonpayable",
    type: "constructor",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "wrappedPosition",
        type: "address",
      },
      {
        internalType: "address",
        name: "pool",
        type: "address",
      },
    ],
    name: "checkPairValidation",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "pool",
        type: "address",
      },
    ],
    name: "checkPoolValidation",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "wrappedPosition",
        type: "address",
      },
    ],
    name: "checkWPValidation",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "bytes32",
        name: "",
        type: "bytes32",
      },
    ],
    name: "pairs",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "",
        type: "address",
      },
    ],
    name: "pools",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "wrappedPosition",
        type: "address",
      },
      {
        internalType: "address",
        name: "pool",
        type: "address",
      },
    ],
    name: "validateAddresses",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "pool",
        type: "address",
      },
    ],
    name: "validatePoolAddress",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "wrappedPosition",
        type: "address",
      },
    ],
    name: "validateWPAddress",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "address",
        name: "",
        type: "address",
      },
    ],
    name: "wrappedPositions",
    outputs: [
      {
        internalType: "bool",
        name: "",
        type: "bool",
      },
    ],
    stateMutability: "view",
    type: "function",
  },
];

const _bytecode =
  "0x608060405234801561001057600080fd5b5061047d806100206000396000f3fe608060405234801561001057600080fd5b50600436106100a35760003560e01c80639221015711610076578063a4063dbc1161005b578063a4063dbc146102b7578063c1c69175146102da578063c6957c281461037757600080fd5b8063922101571461021e57806393795f271461025757600080fd5b806340c5d801146100a85780635027e6ac1461010757806352f57eea1461013e578063673e0481146101fb575b600080fd5b6101056100b63660046103d9565b73ffffffffffffffffffffffffffffffffffffffff16600090815260208190526040902080547fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00166001179055565b005b61012a6101153660046103d9565b60006020819052908152604090205460ff1681565b604051901515815260200160405180910390f35b61010561014c3660046103fb565b6040517fffffffffffffffffffffffffffffffffffffffff000000000000000000000000606084811b8216602084015283901b166034820152600090604801604080517fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe0818403018152918152815160209283012060009081526002909252902080547fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00166001179055505050565b61012a61020936600461042e565b60026020526000908152604090205460ff1681565b61012a61022c3660046103d9565b73ffffffffffffffffffffffffffffffffffffffff1660009081526020819052604090205460ff1690565b6101056102653660046103d9565b73ffffffffffffffffffffffffffffffffffffffff16600090815260016020819052604090912080547fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff00169091179055565b61012a6102c53660046103d9565b60016020526000908152604090205460ff1681565b61012a6102e83660046103fb565b6040517fffffffffffffffffffffffffffffffffffffffff000000000000000000000000606084811b8216602084015283901b1660348201526000908190604801604080518083037fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe001815291815281516020928301206000908152600290925290205460ff16949350505050565b61012a6103853660046103d9565b73ffffffffffffffffffffffffffffffffffffffff1660009081526001602052604090205460ff1690565b803573ffffffffffffffffffffffffffffffffffffffff811681146103d457600080fd5b919050565b6000602082840312156103eb57600080fd5b6103f4826103b0565b9392505050565b6000806040838503121561040e57600080fd5b610417836103b0565b9150610425602084016103b0565b90509250929050565b60006020828403121561044057600080fd5b503591905056fea264697066735822122074778441c11b08bbb428f38ee85ac122cff20dd4b5bf01ac80d2440aceaf4a5c64736f6c634300080a0033";

type MockDeploymentValidatorConstructorParams =
  | [signer?: Signer]
  | ConstructorParameters<typeof ContractFactory>;

const isSuperArgs = (
  xs: MockDeploymentValidatorConstructorParams
): xs is ConstructorParameters<typeof ContractFactory> => xs.length > 1;

export class MockDeploymentValidator__factory extends ContractFactory {
  constructor(...args: MockDeploymentValidatorConstructorParams) {
    if (isSuperArgs(args)) {
      super(...args);
    } else {
      super(_abi, _bytecode, args[0]);
    }
  }

  override deploy(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): Promise<MockDeploymentValidator> {
    return super.deploy(overrides || {}) as Promise<MockDeploymentValidator>;
  }
  override getDeployTransaction(
    overrides?: Overrides & { from?: PromiseOrValue<string> }
  ): TransactionRequest {
    return super.getDeployTransaction(overrides || {});
  }
  override attach(address: string): MockDeploymentValidator {
    return super.attach(address) as MockDeploymentValidator;
  }
  override connect(signer: Signer): MockDeploymentValidator__factory {
    return super.connect(signer) as MockDeploymentValidator__factory;
  }

  static readonly bytecode = _bytecode;
  static readonly abi = _abi;
  static createInterface(): MockDeploymentValidatorInterface {
    return new utils.Interface(_abi) as MockDeploymentValidatorInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): MockDeploymentValidator {
    return new Contract(
      address,
      _abi,
      signerOrProvider
    ) as MockDeploymentValidator;
  }
}