import { ethers } from 'hardhat';
import { deployErc20 } from '../deploy/deploy_erc20';
import { deployUniswap, createPair } from '../deploy/deploy_uniswap';
import abi from '../artifacts/contracts/UniswapBridge.sol/UniswapBridge.json';
import { Contract, Signer } from 'ethers';
import { DefiBridgeProxy, AztecAssetType } from './defi_bridge_proxy';

describe('defi bridge', function () {
  let bridgeProxy: DefiBridgeProxy;
  let uniswapBridgeAddress: string;
  let signer: Signer;
  let signerAddress: string;
  let erc20: Contract;

  beforeAll(async () => {
    [signer] = await ethers.getSigners();
    signerAddress = await signer.getAddress();
    erc20 = await deployErc20(signer);
    const univ2 = await deployUniswap(signer);
    await createPair(signer, univ2, erc20);

    bridgeProxy = await DefiBridgeProxy.deploy(signer);
    uniswapBridgeAddress = await bridgeProxy.deployBridge(signer, abi, [univ2.address]);

    // Bridge proxy can be thought of as the rollup contract. Fund it.
    // TODO: Do for tokens.
    await signer.sendTransaction({
      to: bridgeProxy.address,
      value: 10000n,
    });
  });

  it('should swap ETH to ERC20 tokens', async () => {
    // Call convert to swap ETH to ERC20 tokens and return them to caller.
    const { isAsync, outputValueA, outputValueB } = await bridgeProxy.convert(
      signer,
      uniswapBridgeAddress,
      {
        assetType: AztecAssetType.ETH,
        id: 0,
      },
      {},
      {
        assetType: AztecAssetType.ERC20,
        id: 1,
        erc20Address: erc20.address,
      },
      {},
      1000n,
      1n,
      0n,
    );

    const proxyBalance = BigInt((await erc20.balanceOf(bridgeProxy.address)).toString());
    expect(proxyBalance).toBe(outputValueA);
    expect(outputValueB).toBe(0n);
    expect(isAsync).toBe(false);
  });
});
