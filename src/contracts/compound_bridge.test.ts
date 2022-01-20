import { ethers } from 'hardhat';
import hre from 'hardhat';
import { deployErc20 } from '../deploy/deploy_erc20';
import { deployCompound } from '../deploy/deploy_compound';
import abi from '../artifacts/contracts/CompoundBridge.sol/CompoundBridge.json';
import { Contract, Signer } from 'ethers';
import { DefiBridgeProxy, AztecAssetType } from './defi_bridge_proxy';
import { CBAT_ABI } from '../abi/cTokens';

describe('compound defi bridge', function () {
  let bridgeProxy: DefiBridgeProxy;
  let CompoundBridgeAddress: string;
  let BATaddress: string;
  let cBATaddress: string;
  let cBAT: Contract;
  let signer: Signer;
  let signerAddress: string;

  beforeEach(async () => {

    BATaddress = '0x0d8775f648430679a709e98d2b0cb6250d2887ef';
    cBATaddress = '0x6c8c6b02e7b2be14d4fa6022dfd6d75921d90e4e';
    //signerAddress = '0xde0B295669a9FD93d5F28D9Ec85E40f4cb697BAe';

    [signer] = await ethers.getSigners();
    signerAddress = await signer.getAddress();

    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [signerAddress]
    });

    cBAT = new Contract(cBATaddress, CBAT_ABI, signer);
    bridgeProxy = await DefiBridgeProxy.deploy(signer);
    CompoundBridgeAddress = await bridgeProxy.deployBridge(signer, abi, []);
 
    await signer.sendTransaction({
      to: bridgeProxy.address,
      value: 10000n,
    });
  });

  it('should supply BAT to Compound and get back cBAT', async () => {
    // Call convert to supply tokens to Compound and return cTokens to user.

    const depositBAT = '10000'
    console.log(`Depositing ${depositBAT} BAT`);
    const { isAsync, outputValueA, outputValueB } = await bridgeProxy.convert(
      signer,
      CompoundBridgeAddress,
      {
        assetType: AztecAssetType.ERC20,
        id: 0,
        erc20Address: BATaddress
      },
      {},
      {
        assetType: AztecAssetType.ERC20,
        id: 1,
        erc20Address: cBATaddress
      },
      {},
      10000n,
      1n,
      0n,
    );

    const proxyBalance = BigInt((await cBAT.balanceOf(bridgeProxy.address)).toString());
    expect(proxyBalance).toBe(outputValueA);
    expect(outputValueB).toBe(0n);
    expect(isAsync).toBe(false);
  });
});
