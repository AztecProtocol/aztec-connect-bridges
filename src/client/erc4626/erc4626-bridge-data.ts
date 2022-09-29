import { EthAddress } from "@aztec/barretenberg/address";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { Web3Provider } from "@ethersproject/providers";
import { IERC20Metadata__factory, IERC4626__factory } from "../../../typechain-types";
import { createWeb3Provider } from "../aztec/provider";
import { AuxDataConfig, AztecAsset, BridgeDataFieldGetters, SolidityType, UnderlyingAsset } from "../bridge-data";

export class ERC4626BridgeData implements BridgeDataFieldGetters {
  shareToAssetMap = new Map<EthAddress, EthAddress>();

  protected constructor(protected ethersProvider: Web3Provider) {}

  static create(provider: EthereumProvider) {
    const ethersProvider = createWeb3Provider(provider);
    return new ERC4626BridgeData(ethersProvider);
  }

  auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: "AuxData determine whether issue (0) or redeem flow (1) is executed",
    },
  ];

  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<number[]> {
    // First check whether outputAssetA is a share by calling asset() on it
    let vault = IERC4626__factory.connect(outputAssetA.erc20Address.toString(), this.ethersProvider);
    try {
      const vaultAsset = EthAddress.fromString(await vault.asset());
      if (vaultAsset.equals(inputAssetA.erc20Address)) {
        return [0];
      } else {
        throw "Address of vault's asset isn't equal to inputAssetA.erc20address";
      }
    } catch {
      // Calling asset() on outputAssetA failed --> outputAssetA is not a share but probably an asset
    }

    // Check whether inputAssetA is a share
    vault = IERC4626__factory.connect(inputAssetA.erc20Address.toString(), this.ethersProvider);
    try {
      const vaultAsset = EthAddress.fromString(await vault.asset());
      if (vaultAsset.equals(outputAssetA.erc20Address)) {
        return [1];
      } else {
        throw "Address of vault's asset isn't equal to outputAssetA.erc20address";
      }
    } catch {
      throw "Neither input nor output asset is a share of an ERC4626 vault";
    }
  }

  async getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: number,
    inputValue: bigint,
  ): Promise<bigint[]> {
    if (auxData === 0) {
      // Issuing
      const shareAddress = outputAssetA.erc20Address;
      const vault = IERC4626__factory.connect(shareAddress.toString(), this.ethersProvider);
      const amountOut = await vault.previewDeposit(inputValue);
      return [amountOut.toBigInt()];
    } else if (auxData === 1) {
      // Redeeming
      const shareAddress = inputAssetA.erc20Address;
      const vault = IERC4626__factory.connect(shareAddress.toString(), this.ethersProvider);
      const amountOut = await vault.previewRedeem(inputValue);
      return [amountOut.toBigInt()];
    } else {
      throw "Invalid auxData";
    }
  }

  /**
   * @notice Gets asset for a given share
   * @param share Address of the share/vault
   * @return Address of the underlying asset
   */
  async getAsset(share: EthAddress): Promise<EthAddress> {
    let asset = this.shareToAssetMap.get(share);
    if (asset === undefined) {
      const vault = IERC4626__factory.connect(share.toString(), this.ethersProvider);
      asset = EthAddress.fromString(await vault.asset());
      this.shareToAssetMap.set(share, asset);
    }
    return asset;
  }

  /**
   * @notice This function gets the underlying amount of asset corresponding to shares
   * @param share Address of the share/vault
   * @param amount Amount of shares to get underlying amount for
   * @return Underlying amount of asset corresponding to the amount of shares
   */
  async getUnderlyingAmount(share: AztecAsset, amount: bigint): Promise<UnderlyingAsset> {
    const vault = IERC4626__factory.connect(share.erc20Address.toString(), this.ethersProvider);
    const assetAddress = EthAddress.fromString(await vault.asset());

    const tokenContract = IERC20Metadata__factory.connect(assetAddress.toString(), this.ethersProvider);
    const namePromise = tokenContract.name();
    const symbolPromise = tokenContract.symbol();
    const decimalsPromise = tokenContract.decimals();
    const amountPromise = vault.previewRedeem(amount);

    return {
      address: assetAddress,
      name: await namePromise,
      symbol: await symbolPromise,
      decimals: await decimalsPromise,
      amount: (await amountPromise).toBigInt(),
    };
  }
}
