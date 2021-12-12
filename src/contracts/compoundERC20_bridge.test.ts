import { ethers } from 'hardhat';
import { deployErc20 } from '../deploy/deploy_erc20';
import { deployCToken } from '../deploy/deploy_compound';
import abi from '../artifacts/contracts/CompoundERC20Bridge.sol/CompoundERC20Bridge.json';
import { Contract, Signer } from 'ethers';
import { DefiBridgeProxy, AztecAssetType } from './defi_bridge_proxy';

describe('defi bridge', function () {
  let bridgeProxy: DefiBridgeProxy;
  let CompoundBridgeAddress: string;
  let signer: Signer;
  let signerAddress: string;
  let erc20: Contract;

  beforeAll(async () => {
    [signer] = await ethers.getSigners();
    signerAddress = await signer.getAddress();
    erc20 = await deployErc20(signer);
    const compound = await deployCToken(signer);
    bridgeProxy = await DefiBridgeProxy.deploy(signer);
    CompoundBridgeAddress = await bridgeProxy.deployBridge(signer, abi, [compound.address]);

    // Bridge proxy can be thought of as the rollup contract. Fund it.
    // TODO: Do for tokens.
    await signer.sendTransaction({
      to: bridgeProxy.address,
      value: 10000n,
    });
  });

  it('should supply to Compound', async () => {
    // Call convert to supply tokens to Compound and return cTokens to user.
    const { isAsync, outputValueA, outputValueB } = await bridgeProxy.convert(
      signer,
      CompoundBridgeAddress,
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
