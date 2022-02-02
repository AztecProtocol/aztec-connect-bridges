import { Contract, Signer } from "ethers";
import ProviderAbi from "./artifacts/contracts/interfaces/ICurveProvider.sol/ICurveProvider.json";
import FactoryAbi from "./artifacts/contracts/interfaces/ICurveFactory.sol/ICurveFactory.json";
import RegistryAbi from "./artifacts/contracts/interfaces/ICurveRegistry.sol/ICurveRegistry.json";
import Zap from "./artifacts/contracts/interfaces/ICurveZap.sol/ICurveZap.json";
import CurveStablePool from "./artifacts/contracts/interfaces/ICurveStablePool.sol/ICurveStablePool.json";
import { Uniswap } from "./uniswap";
import { addressesAreSame, fixEthersStackTrace, getTokenBalance, approveToken, transferToken, Constants } from "./utils";

const PROVIDER_ADDRESS = "0x0000000022D53366457F9d5E68Ec105046FC4383";
const ZAP_ADDRESS = "0xA79828DF1850E8a3A3064576f380D90aECDD3359";
const FACTORY_ADDRESS = "0x0959158b6040D32d04c301A72CBFD6b39E21c9AE";

export class Curve {
  private providerContract?: Contract;
  private registryContract?: Contract;
  private factoryContract?: Contract;
  private zapDepositor?: Contract;

  constructor(private signer: Signer) {
  }

  async init() {
    this.providerContract = new Contract(PROVIDER_ADDRESS, ProviderAbi.abi, this.signer);
    const registryAddress = await this.providerContract.get_registry();
    this.registryContract = new Contract(registryAddress, RegistryAbi.abi, this.signer);
    this.factoryContract = new Contract(FACTORY_ADDRESS, FactoryAbi.abi, this.signer);
    this.zapDepositor = new Contract(ZAP_ADDRESS, Zap.abi, this.signer);
  }


  async logAllStablePools() {
    const poolCount = (await this.registryContract!.pool_count()).toNumber();
    const mappings = new Map<string, string>();
    for (let i = 0; i < poolCount; i++) {
      const poolAddress = (await this.registryContract!.pool_list(i)).toString();
      const tokenAddress = (await this.registryContract!.get_lp_token(poolAddress));
      mappings.set(poolAddress, tokenAddress);
    }
    console.log("Token mappings ", mappings);
  }

  async logAllMetaPools() {
    const poolCount = (await this.factoryContract!.pool_count()).toNumber();
    const tokens = [];
    for (let i = 0; i < poolCount; i++) {
      const poolAddress = (await this.factoryContract!.pool_list(i)).toString();
      tokens.push(poolAddress);
    }
    console.log("Tokens ", tokens);
  }

  async depositToStablePool(    
    recipient: string,
    token: { erc20Address: string; amount: bigint; name: string },
    amountInMaximum: bigint
  ){
    let maxAmountToDeposit = amountInMaximum;    
    const poolAddress = (await this.registryContract!.get_pool_from_lp_token(token.erc20Address)).toString();
    const numCoinsResult = await this.registryContract!.get_n_coins(poolAddress);
    const numCoins = numCoinsResult[1].toNumber();
    const coins = await this.registryContract!.get_coins(poolAddress);
    const inputAssetIndex = this.findPreferredAssset(coins);
    if (inputAssetIndex === -1) {
      throw new Error('Asset not supported');
    }
    const inputAsset = coins[inputAssetIndex];
    const signerAddress = await this.signer.getAddress();
    if (inputAsset != Constants.ETH) {
      // need to uniswap to the preferred input asset
      const uniswap = new Uniswap(this.signer);
      await uniswap.swapFromEth(signerAddress, {erc20Address: inputAsset, amount: token.amount, name: inputAsset }, amountInMaximum);
      maxAmountToDeposit = await getTokenBalance(inputAsset, signerAddress, this.signer);
    }
    await approveToken(
      inputAsset,
      poolAddress,
      this.signer,
      maxAmountToDeposit
    );
    const amounts = new Array(numCoins).fill(0n);
    amounts[inputAssetIndex] = amountInMaximum;
    const poolContract = new Contract(poolAddress, CurveStablePool.abi, this.signer);
    const depositFunc =
    poolContract.functions[
        `add_liquidity(uint256[${numCoins}],uint256)`
      ];
    const depositResponse = await depositFunc(
      amounts,
      0n,
      {value: inputAsset === Constants.ETH ? amountInMaximum : 0n}
    ).catch(fixEthersStackTrace);
    await depositResponse.wait();
    const lpTokenBalance = await getTokenBalance(token.erc20Address, signerAddress, this.signer);
    await transferToken(token.erc20Address, recipient, this.signer, lpTokenBalance);
  }

  findPreferredAssset(availableAssets: string[]) {
    const ethIndex = availableAssets.findIndex(asset => addressesAreSame(asset, Constants.ETH));
    if (ethIndex !== -1) {
      return ethIndex;
    }
    const wethIndex = availableAssets.findIndex(asset => addressesAreSame(asset, Constants.WETH9));
    if (wethIndex !== -1) {
      return wethIndex;
    }
    const stableIndex = availableAssets.findIndex(asset => Uniswap.isSupportedAsset(asset));
    return stableIndex;
  }
  
  async depositToMetaPool(
    recipient: string,
    token: { erc20Address: string; amount: bigint; name: string },
    amountInMaximum: bigint,
  ) {
    let maxAmountToDeposit = amountInMaximum;
    const numCoinsResult = await this.factoryContract!.get_n_coins(token.erc20Address);
    const numCoins = numCoinsResult[1].toNumber();
    const coins = await this.factoryContract!.get_underlying_coins(token.erc20Address);
    const inputAssetIndex = this.findPreferredAssset(coins);
    if (inputAssetIndex === -1) {
      throw new Error('Asset not supported');
    }
    const inputAsset = coins[inputAssetIndex];
    const signerAddress = await this.signer.getAddress();
    if (inputAsset != Constants.ETH) {
      // need to uniswap to the preferred input asset
      const uniswap = new Uniswap(this.signer);
      await uniswap.swapFromEth(signerAddress, {erc20Address: inputAsset, amount: token.amount, name: inputAsset }, amountInMaximum);
      maxAmountToDeposit = await getTokenBalance(inputAsset, signerAddress, this.signer);
    }

    await approveToken(
      inputAsset,
      ZAP_ADDRESS,
      this.signer,
      maxAmountToDeposit
    );

    const amounts = new Array(numCoins).fill(0n);
    amounts[inputAssetIndex] = maxAmountToDeposit;
    const depositFunc =
      this.zapDepositor!.functions[
        `add_liquidity(address,uint256[${numCoins}],uint256,address)`
      ];
    const depositResponse = await depositFunc(
      token.erc20Address,
      amounts,
      0n,
      recipient,
      {value: inputAsset === Constants.ETH ? amountInMaximum : 0n}
    ).catch(fixEthersStackTrace);
    await depositResponse.wait();
  }

  async getPoolForLpToken(lpTokenAddress: string) {
    const poolAddress = (await this.registryContract!.get_pool_from_lp_token(lpTokenAddress)).toString();
    return poolAddress;
  }

  async isMetaPool(lpTokenAddress: string) {
    const poolAddress = await this.getPoolForLpToken(lpTokenAddress);
    // for meta pools, the pool is the lp token. for stable pools, it's not
    return addressesAreSame(poolAddress, lpTokenAddress);
  }

  async swap(
    recipient: string,
    outputToken: { erc20Address: string; amount: bigint; name: string },
    amountInMaximum: bigint
  ) {
    const uniswap = new Uniswap(this.signer);
    if (Uniswap.isSupportedAsset(outputToken.erc20Address)) {
      await uniswap.swapFromEth(recipient, outputToken, amountInMaximum);
      return;
    }
    const isMetaPool = await this.isMetaPool(outputToken.erc20Address);
    if (isMetaPool) {
      await this.depositToMetaPool(recipient, outputToken, amountInMaximum);
      return;
    }
    await this.depositToStablePool(recipient, outputToken, amountInMaximum);
  }
}
