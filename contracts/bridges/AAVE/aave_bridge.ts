import { Contract, ContractFactory, ethers, Signer } from "ethers";
import AaveLendingBridge from "../../../src/artifacts/contracts/bridges/AAVE/AAVELending.sol/AaveLendingBridge.json";

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

export class AaveBridge {
  private contract: Contract;

  constructor(public address: string, signer: Signer) {
    this.contract = new Contract(this.address, AaveLendingBridge.abi, signer);
  }

  static async deploy(signer: Signer, args: any[]) {
    const factory = new ContractFactory(
      AaveLendingBridge.abi,
      AaveLendingBridge.bytecode,
      signer
    );
    const contract = await factory.deploy(...args);
    return new AaveBridge(contract.address, signer);
  }

  async canFinalise(interactionNonce: bigint) {
    return await this.contract.canFinalise(interactionNonce);
  }

  async setUnderlyingToZkAToken(
    signer: Signer,
    asset: string,
    options: SendTxOptions = {}
  ) {
    const contract = new Contract(
      this.contract.address,
      this.contract.interface,
      signer
    );
    return await contract.setUnderlyingToZkAToken(asset);
  }
}
