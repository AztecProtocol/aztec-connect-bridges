import { Contract, ContractFactory, ethers, Signer } from "ethers";
import Element from "./artifacts/contracts/bridges/ElementFinance/ElementBridge.sol/ElementBridge.json";

export interface SendTxOptions {
  gasPrice?: bigint;
  gasLimit?: number;
}

const assetToArray = (asset: AztecAsset) => [
  asset.id || 0,
  asset.erc20Address || "0x0000000000000000000000000000000000000000",
  asset.assetType || 0,
];

export enum AztecAssetType {
  NOT_USED,
  ETH,
  ERC20,
  VIRTUAL,
}

export interface AztecAsset {
  id?: number;
  assetType?: AztecAssetType;
  erc20Address?: string;
}

export interface TestToken {
  amount: bigint;
  erc20Address: string;
}

export class ElementBridge {
  private contract: Contract;

  constructor(public address: string, signer: Signer) {
    this.contract = new Contract(this.address, Element.abi, signer);
  }

  static async deploy(signer: Signer, args: any[]) {
    const factory = new ContractFactory(Element.abi, Element.bytecode, signer);
    const contract = await factory.deploy(...args);
    return new ElementBridge(contract.address, signer);
  }

  async canFinalise(interactionNonce: bigint) {
    return await this.contract.canFinalise(interactionNonce);
  }

  async registerConvergentPoolAddress(
    signer: Signer,
    wrappedPositionAddress: string,
    poolAddress: string,
    expiry: number,
    options: SendTxOptions = {}
  ) {
    const contract = new Contract(
      this.contract.address,
      this.contract.interface,
      signer
    );
    const tx = await contract.registerConvergentPoolAddress(
      wrappedPositionAddress,
      poolAddress,
      expiry
    );
    await tx.wait();
  }
}
