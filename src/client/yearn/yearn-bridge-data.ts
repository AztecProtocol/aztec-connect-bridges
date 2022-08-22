import { EthAddress } from "@aztec/barretenberg/address";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { Web3Provider } from "@ethersproject/providers";
import { createWeb3Provider } from "../aztec/provider";
import { BigNumber } from "ethers";

import "isomorphic-fetch";

import { AuxDataConfig, AztecAsset, AztecAssetType, BridgeDataFieldGetters, SolidityType } from "../bridge-data";
import {
  IYearnRegistry,
  IYearnRegistry__factory,
  IYearnVault__factory,
  IRollupProcessor,
  IRollupProcessor__factory,
} from "../../../typechain-types";
import { AssetValue } from "@aztec/barretenberg/asset";

export class YearnBridgeData implements BridgeDataFieldGetters {
  allYvETH?: EthAddress[];
  allVaultsForTokens?: { [key: string]: EthAddress[] };
  wETH = "0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2";

  constructor(
    private ethersProvider: Web3Provider,
    private yRegistry: IYearnRegistry,
    private rollupProcessor: IRollupProcessor,
  ) {}

  static create(provider: EthereumProvider) {
    const ethersProvider = createWeb3Provider(provider);
    return new YearnBridgeData(
      ethersProvider,
      IYearnRegistry__factory.connect("0x50c1a2eA0a861A967D9d0FFE2AE4012c2E053804", ethersProvider),
      IRollupProcessor__factory.connect("0xFF1F2B4ADb9dF6FC8eAFecDcbF96A2B351680455", ethersProvider),
    );
  }

  auxDataConfig: AuxDataConfig[] = [
    {
      start: 0,
      length: 64,
      solidityType: SolidityType.uint64,
      description: "AuxData determine whether deposit (0) or withdraw flow (1) is executed",
    },
  ];

  async getAuxData(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
  ): Promise<number[]> {
    const [allYvETH, allVaultsForTokens] = await this.getAllVaultsAndTokens();

    if (!(await this.isSupportedAsset(inputAssetA))) {
      throw "inputAssetA not supported";
    }
    if (!(await this.isSupportedAsset(outputAssetA))) {
      throw "outputAssetA not supported";
    }

    if (inputAssetA.assetType == AztecAssetType.ETH || outputAssetA.assetType == AztecAssetType.ETH) {
      if (
        inputAssetA.assetType == AztecAssetType.ETH && // Check if we are depositing ETH
        outputAssetA.assetType == AztecAssetType.ERC20 && // Check if we are receiving ERC20
        allYvETH.findIndex(token => token.toString() === outputAssetA.erc20Address.toString()) > -1 // Check if we are receiving yvETH
      ) {
        return [0]; // deposit via zap
      } else if (
        inputAssetA.assetType == AztecAssetType.ERC20 && // Check if we are withdrawing ERC20
        allYvETH.findIndex(token => token.toString() === inputAssetA.erc20Address.toString()) > -1 && // Check if we are withdrawing from yvETH
        outputAssetA.assetType == AztecAssetType.ETH // Check if we are receiving ETH
      ) {
        return [1]; // withdraw via zap
      } else {
        throw "Invalid input and/or output asset";
      }
    }

    const hasInputAsset = allVaultsForTokens[inputAssetA.erc20Address.toString()] || [];
    const hasOutputAsset = allVaultsForTokens[outputAssetA.erc20Address.toString()] || [];

    // standard deposit
    const matchDepositSituation = hasInputAsset && hasInputAsset.findIndex(token => token.toString() === outputAssetA.erc20Address.toString()) > -1;
    if (matchDepositSituation) {
        return [0];
    }
    // standard withdraw
    const matchWithdrawSituation = hasOutputAsset && hasOutputAsset.findIndex(token => token.toString() === inputAssetA.erc20Address.toString()) > -1;
    if (matchWithdrawSituation) {
        return [1];
    }
    throw "Invalid input and/or output asset";
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
      let tokenAddress = inputAssetA.erc20Address.toString();
      if (inputAssetA.assetType == AztecAssetType.ETH) {
        // Deposit via zap
        tokenAddress = this.wETH;
      }
      const yvTokenAddress = await this.yRegistry.latestVault(tokenAddress);
      const yvTokenContract = IYearnVault__factory.connect(yvTokenAddress, this.ethersProvider);
      const [pricePerShare, decimals] = await Promise.all([
        yvTokenContract.pricePerShare(),
        yvTokenContract.decimals(),
      ]);
      const expectedShares = BigNumber.from(inputValue).mul(BigNumber.from(10).pow(decimals)).div(pricePerShare);
      return [expectedShares.toBigInt(), 0n];
    }
    if (auxData === 1) {
      let tokenAddress = outputAssetA.erc20Address.toString();
      if (outputAssetA.assetType == AztecAssetType.ETH) {
        // Withdraw via zap
        tokenAddress = this.wETH;
      }
      const yvTokenAddress = await this.yRegistry.latestVault(tokenAddress);
      const yvTokenContract = IYearnVault__factory.connect(yvTokenAddress, this.ethersProvider);
      const [pricePerShare, decimals] = await Promise.all([
        yvTokenContract.pricePerShare(),
        yvTokenContract.decimals(),
      ]);
      const expectedUnderlying = BigNumber.from(inputValue).mul(pricePerShare).div(BigNumber.from(10).pow(decimals));
      return [expectedUnderlying.toBigInt(), 0n];
    }
    throw "Invalid auxData";
  }

  // @param yieldAsset in this case yieldAsset are yv tokens (e.g. yvDai, yvEth, etc.)
  async getAPR(yieldAsset: AztecAsset): Promise<number> {
    type TminVaultStruct = {
      address: string;
      apy: {
        gross_apr: number;
      };
    };
    const allVaults = (await (
      await fetch("https://api.yearn.finance/v1/chains/1/vaults/all")
    ).json()) as TminVaultStruct[];
    const currentVault = allVaults.find((vault: TminVaultStruct) =>
      EthAddress.fromString(vault.address).equals(yieldAsset.erc20Address),
    );
    if (currentVault) {
      const grossAPR = currentVault.apy.gross_apr;
      return grossAPR * 100;
    }
    return 0;
  }

  async getMarketSize(
    underlying: AztecAsset,
    inputAssetB: AztecAsset,
    yvToken: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: number,
  ): Promise<AssetValue[]> {
    const yvTokenContract = IYearnVault__factory.connect(yvToken.erc20Address.toString(), this.ethersProvider);
    const totalAssets = await yvTokenContract.totalAssets();
    return [{ assetId: underlying.id, value: totalAssets.toBigInt() }];
  }

  private async isSupportedAsset(asset: AztecAsset): Promise<boolean> {
    if (asset.assetType == AztecAssetType.ETH) return true;

    const assetAddress = EthAddress.fromString(await this.rollupProcessor.getSupportedAsset(asset.id));
    return assetAddress.equals(asset.erc20Address);
  }

  private async getAllVaultsAndTokens(): Promise<[EthAddress[], { [key: string]: EthAddress[] }]> {
    const allYvETH: EthAddress[] = this.allYvETH || [];
    const allVaultsForTokens: { [key: string]: EthAddress[] } = this.allVaultsForTokens || {};

    if (!this.allVaultsForTokens) {
      const numTokens = await this.yRegistry.numTokens();
      for (let index = 0; index < Number(numTokens); index++) {
        const token = await this.yRegistry.tokens(index);
        const vault = await this.yRegistry.latestVault(token);
        if (!allVaultsForTokens[token]) {
          allVaultsForTokens[token] = [];
        }
        allVaultsForTokens[token].push(EthAddress.fromString(vault));
        if (token === this.wETH) {
          allYvETH.push(EthAddress.fromString(vault));
        }
      }
      this.allYvETH = allYvETH;
    }
    return [allYvETH, allVaultsForTokens];
  }
}
