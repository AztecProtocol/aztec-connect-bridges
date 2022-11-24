/* Autogenerated file. Do not edit manually. */
/* tslint:disable */
/* eslint-disable */

import { Contract, Signer, utils } from "ethers";
import type { Provider } from "@ethersproject/providers";
import type {
  IExchangeIssuance,
  IExchangeIssuanceInterface,
} from "../IExchangeIssuance";

const _abi = [
  {
    inputs: [
      {
        internalType: "contract ISetToken",
        name: "_setToken",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountSetToken",
        type: "uint256",
      },
    ],
    name: "issueExactSetFromETH",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "payable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "contract ISetToken",
        name: "_setToken",
        type: "address",
      },
      {
        internalType: "contract IERC20",
        name: "_inputToken",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountSetToken",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_maxAmountInputToken",
        type: "uint256",
      },
    ],
    name: "issueExactSetFromToken",
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
    inputs: [
      {
        internalType: "contract ISetToken",
        name: "_setToken",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_minSetReceive",
        type: "uint256",
      },
    ],
    name: "issueSetForExactETH",
    outputs: [
      {
        internalType: "uint256",
        name: "",
        type: "uint256",
      },
    ],
    stateMutability: "payable",
    type: "function",
  },
  {
    inputs: [
      {
        internalType: "contract ISetToken",
        name: "_setToken",
        type: "address",
      },
      {
        internalType: "contract IERC20",
        name: "_inputToken",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountInput",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_minSetReceive",
        type: "uint256",
      },
    ],
    name: "issueSetForExactToken",
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
    inputs: [
      {
        internalType: "contract ISetToken",
        name: "_setToken",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountSetToken",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_minEthOut",
        type: "uint256",
      },
    ],
    name: "redeemExactSetForETH",
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
    inputs: [
      {
        internalType: "contract ISetToken",
        name: "_setToken",
        type: "address",
      },
      {
        internalType: "contract IERC20",
        name: "_outputToken",
        type: "address",
      },
      {
        internalType: "uint256",
        name: "_amountSetToken",
        type: "uint256",
      },
      {
        internalType: "uint256",
        name: "_minOutputReceive",
        type: "uint256",
      },
    ],
    name: "redeemExactSetForToken",
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
];

export class IExchangeIssuance__factory {
  static readonly abi = _abi;
  static createInterface(): IExchangeIssuanceInterface {
    return new utils.Interface(_abi) as IExchangeIssuanceInterface;
  }
  static connect(
    address: string,
    signerOrProvider: Signer | Provider
  ): IExchangeIssuance {
    return new Contract(address, _abi, signerOrProvider) as IExchangeIssuance;
  }
}
