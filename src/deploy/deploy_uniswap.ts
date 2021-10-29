#!/usr/bin/env node
import { ContractTransaction } from '@ethersproject/contracts';
import UniswapV2FactoryJson from '@uniswap/v2-core/build/UniswapV2Factory.json';
import UniswapV2PairJson from '@uniswap/v2-core/build/UniswapV2Pair.json';
import IWETH from '@uniswap/v2-periphery/build/IWETH.json';
import WETH9 from '@uniswap/v2-periphery/build/WETH9.json';
import UniswapV2Router02Json from '@uniswap/v2-periphery/build/UniswapV2Router02.json';
import { Contract, ContractFactory, Signer } from 'ethers';

export const createPair = async (
  owner: Signer,
  router: Contract,
  asset: Contract,
  initialTokenSupply = 1000n * 10n ** 18n,
  initialEthSupply = 10n ** 18n,
) => {
  const factory = new Contract(await router.factory(), UniswapV2FactoryJson.abi, owner);
  const weth = new Contract(await router.WETH(), IWETH.abi, owner);
  const ZERO_ADDRESS = '0x0000000000000000000000000000000000000000';

  if ((await factory.getPair(asset.address, weth.address)) != ZERO_ADDRESS) {
    console.log(`UniswapPair [${await asset.name()} - WETH] already created.`);
    return;
  }

  const minConfirmations = [1337, 31337].indexOf(await owner.getChainId()) >= 0 ? 1 : 3;
  const withConfirmation = async (action: Promise<ContractTransaction>) => {
    const tx2 = await action;
    await tx2.wait(minConfirmations);
  };

  console.log(`Create UniswapPair [${await asset.name()} - WETH]...`);
  await withConfirmation(factory.createPair(asset.address, weth.address));
  const pairAddress = await factory.getPair(asset.address, weth.address);
  const pair = new Contract(pairAddress, UniswapV2PairJson.abi, owner);
  console.log(`Pair contract address: ${pairAddress}`);

  await withConfirmation(asset.mint(pair.address, initialTokenSupply));

  await withConfirmation(weth.deposit({ value: initialEthSupply }));
  await withConfirmation(weth.transfer(pair.address, initialEthSupply));

  // Don't do this in production.
  await pair.mint(await owner.getAddress());
  console.log(`Initial token supply: ${initialTokenSupply}`);
  console.log(`Initial ETH supply: ${initialEthSupply}`);
};

export const deployUniswap = async (owner: Signer) => {
  console.log('Deploying UniswapFactory...');
  const UniswapFactory = new ContractFactory(UniswapV2FactoryJson.abi, UniswapV2FactoryJson.bytecode, owner);
  const factory = await UniswapFactory.deploy(await owner.getAddress());
  console.log(`UniswapFactory contract address: ${factory.address}`);

  console.log('Deploying WETH...');
  const WETHFactory = new ContractFactory(WETH9.abi, WETH9.bytecode, owner);
  const weth = await WETHFactory.deploy();
  console.log(`WETH contract address: ${weth.address}`);

  console.log('Deploying UniswapV2Router...');
  const UniswapV2Router = new ContractFactory(UniswapV2Router02Json.abi, UniswapV2Router02Json.bytecode, owner);
  const router = await UniswapV2Router.deploy(factory.address, weth.address);
  console.log(`UniswapV2Router contract address: ${router.address}`);

  return router;
};
