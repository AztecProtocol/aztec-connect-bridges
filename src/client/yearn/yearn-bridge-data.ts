import { EthAddress } from "@aztec/barretenberg/address";
import { EthereumProvider } from "@aztec/barretenberg/blockchain";
import { Web3Provider } from "@ethersproject/providers";
import { createWeb3Provider } from "../aztec/provider";
import { BigNumber, utils } from "ethers";
import {
  AuxDataConfig,
  AztecAsset,
  AztecAssetType,
  BridgeDataFieldGetters,
  SolidityType
} from "../bridge-data";
import {
  IYearnRegistry,
  IYearnRegistry__factory,
  IYearnVault__factory,
  IRollupProcessor,
  IRollupProcessor__factory,
} from "../../../typechain-types";

export class YearnBridgeData implements BridgeDataFieldGetters {
  allVaults?: EthAddress[];
  allUnderlying?: EthAddress[];
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
  ): Promise<bigint[]> {
    const [allVaults, allUnderlying] = await this.getAllVaultsAndTokens();

    if (!(await this.isSupportedAsset(inputAssetA))) {
      throw "inputAssetA not supported";
    }
    if (!(await this.isSupportedAsset(outputAssetA))) {
      throw "outputAssetA not supported";
    }

    if (inputAssetA.assetType == AztecAssetType.ETH && outputAssetA.assetType == AztecAssetType.ERC20) {
      return [0n]; // deposit via zap
    } else if (inputAssetA.assetType == AztecAssetType.ERC20 && outputAssetA.assetType == AztecAssetType.ETH) {
      return [1n]; // withdraw via zap
    }

    const inputAssetAIsUnderlying = allUnderlying.includes(inputAssetA.erc20Address);
    const outputAssetAIsVault = allVaults.includes(outputAssetA.erc20Address);
    if(inputAssetAIsUnderlying && outputAssetAIsVault) {
      return [0n]; // standard deposit
    } else if(!inputAssetAIsUnderlying && !outputAssetAIsVault) {
      return [1n]; // standard withdraw
    }
    throw "Invalid input and/or output asset";
  }

  async getExpectedOutput(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    inputValue: bigint,
  ): Promise<bigint[]> {
    if (auxData === 0n && inputAssetA.assetType == AztecAssetType.ETH) {
      //Deposit via zap
      const yvETHAddress = await this.yRegistry.latestVault(this.wETH);
      const yvETHContract = IYearnVault__factory.connect(yvETHAddress, this.ethersProvider);
      const pricePerShare = utils.formatEther(await yvETHContract.pricePerShare());
      const amount = utils.formatEther(inputValue);
      const expectedShares = utils.parseEther(String(Number(amount) / Number(pricePerShare)));

      return [BigNumber.from(expectedShares).toBigInt(), 0n];
    }
    if (auxData === 1n && outputAssetA.assetType == AztecAssetType.ETH) {
      //Withdraw via zap
      const yvETHAddress = await this.yRegistry.latestVault(this.wETH);
      const yvETHContract = IYearnVault__factory.connect(yvETHAddress, this.ethersProvider);
      const pricePerShare = utils.formatEther(await yvETHContract.pricePerShare());
      const shares = utils.formatEther(inputValue);
      const expectedShares = utils.parseEther(String(Number(shares) * Number(pricePerShare)));

      return [BigNumber.from(expectedShares).toBigInt(), 0n];
    }

    if (auxData === 0n && inputAssetA.assetType == AztecAssetType.ERC20) {
      //Standard Deposit
      const yvTokenAddress = await this.yRegistry.latestVault(inputAssetA.erc20Address);
      const yvTokenContract = IYearnVault__factory.connect(yvTokenAddress, this.ethersProvider);
      const decimals = await yvTokenContract.decimals();
      const pricePerShare = utils.formatUnits(await yvTokenContract.pricePerShare(), decimals);
      const amount = utils.formatUnits(inputValue, decimals);
      const expectedShares = utils.parseUnits(String(Number(amount) / Number(pricePerShare)), decimals);

      return [BigNumber.from(expectedShares).toBigInt(), 0n];
    }
    if (auxData === 1n && outputAssetA.assetType == AztecAssetType.ERC20) {
      //Standard Withdraw
      const yvTokenAddress = await this.yRegistry.latestVault(this.wETH);
      const yvTokenContract = IYearnVault__factory.connect(yvTokenAddress, this.ethersProvider);
      const decimals = await yvTokenContract.decimals();
      const pricePerShare = utils.formatUnits(await yvTokenContract.pricePerShare(), decimals);
      const shares = utils.formatUnits(inputValue, decimals);
      const expectedShares = utils.parseUnits(String(Number(shares) * Number(pricePerShare)), decimals);

      return [BigNumber.from(expectedShares).toBigInt(), 0n];
    }

    throw "Invalid auxData";
  }

  async getExpectedYield?(
    inputAssetA: AztecAsset,
    inputAssetB: AztecAsset,
    outputAssetA: AztecAsset,
    outputAssetB: AztecAsset,
    auxData: bigint,
    inputValue: bigint,
  ): Promise<number[]> {
    const yvTokenAddress = await this.yRegistry.latestVault(inputAssetA.erc20Address);
    const allVaults = await (await fetch("https://api.yearn.finance/v1/chains/1/vaults/all")).json();
    const currentVault = allVaults.find((vault) => vault.address.toLowerCase() == yvTokenAddress.toLowerCase());
    if (!currentVault) {
      const grossAPR = currentVault.apy.gross_apr;
      return [grossAPR * 100, 0];
    }
    return [0, 0];
  }

  private async isSupportedAsset(asset: AztecAsset): Promise<boolean> {
    if (asset.assetType == AztecAssetType.ETH) return true;

    const assetAddress = EthAddress.fromString(await this.rollupProcessor.getSupportedAsset(asset.id));
    return assetAddress.equals(asset.erc20Address);
  }

  private async getAllVaultsAndTokens(): Promise<[EthAddress[], EthAddress[]]> {
    const allVaults: EthAddress[] = this.allVaults || [];
    const allUnderlying: EthAddress[] = this.allUnderlying || [];
    if (!this.allVaults) {
      const numTokens = await this.yRegistry.numTokens();
      for (let index = 0; index < numTokens; index++) {
        const token = await this.yRegistry.tokens(index);
        const vault = await this.yRegistry.latestVault(token);
        allVaults.push(EthAddress.fromString(vault));
        allUnderlying.push(EthAddress.fromString(token));
      }
    }
    return [allVaults, allUnderlying];
  }
}
