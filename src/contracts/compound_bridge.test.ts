import { ethers } from 'hardhat';
import hre from 'hardhat';
import { deployErc20 } from '../deploy/deploy_erc20';
import { deployCompound } from '../deploy/deploy_compound';
import abi from '../artifacts/contracts/CompoundBridge.sol/CompoundBridge.json';
import { Contract, Signer } from 'ethers';
import { DefiBridgeProxy, AztecAssetType } from './defi_bridge_proxy';
import { formatEther, parseEther } from '@ethersproject/units';
import { CAAVE_ABI, CBAT_ABI, CCOMP_ABI, CDAI_ABI, CETH_ABI, CLINK_ABI, CMKR_ABI, CSUSHI_ABI, CTUSD_ABI, CUNI_ABI, CUSDC_ABI, CUSDP_ABI, CUSDT_ABI, CWBTC2_ABI, CYFI_ABI, CZRX_ABI } from '../abi/cTokens';
import { ERC20_ABI } from '../abi/genericErc20';

describe('compound defi bridge', function () {
  let bridgeProxy: DefiBridgeProxy;
  let CompoundBridgeAddress: string;

  let AAVEaddress  : string; 
  let BATaddress   : string;  
  let COMPaddress  : string; 
  let DAIaddress   : string;
  let LINKaddress  : string; 
  let MKRaddress   : string;  
  let SUSHIaddress : string;
  let TUSDaddress  : string; 
  let UNIaddress   : string;  
  let USDCaddress  : string;
  let USDPaddress  : string; 
  let USDTaddress  : string;
  let WBTCaddress  : string;
  let YFIaddress   : string;
  let ZRXaddress   : string;

  let cAAVEaddress  : string;
  let cBATaddress   : string;
  let cCOMPaddress  : string;
  let cDAIaddress   : string;
  let cETHaddress   : string;
  let cLINKaddress  : string;
  let cMKRaddress   : string;
  let cSUSHIaddress : string;
  let cTUSDaddress  : string;
  let cUNIaddress   : string;
  let cUSDCaddress  : string;
  let cUSDPaddress  : string;
  let cUSDTaddress  : string;
  let cWBTC2address : string;
  let cYFIaddress   : string;
  let cZRXaddress   : string;

  let AAVE:  Contract;
  let BAT:   Contract;
  let COMP:  Contract;
  let DAI:   Contract;
  let LINK:  Contract;
  let MKR:   Contract;
  let SUSHI: Contract;
  let TUSD:  Contract;
  let UNI:   Contract;
  let USDC:  Contract;
  let USDP:  Contract;
  let USDT:  Contract;
  let WBTC2: Contract;
  let YFI:   Contract;
  let ZRX:   Contract;

  let cAAVE:  Contract;
  let cBAT:   Contract;
  let cCOMP:  Contract;
  let cDAI:   Contract;
  let cETH:   Contract;
  let cLINK:  Contract;
  let cMKR:   Contract;
  let cSUSHI: Contract;
  let cTUSD:  Contract;
  let cUNI:   Contract;
  let cUSDC:  Contract;
  let cUSDP:  Contract;
  let cUSDT:  Contract;
  let cWBTC2: Contract;
  let cYFI:   Contract;
  let cZRX:   Contract;

  let signer: Signer;
  let signerAddress: string;
  let signerERC20balance: bigint;
  let bridgeERC20balance: bigint;
  let depositERC20amount: bigint;

  beforeEach(async () => {

    AAVEaddress   = '0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9';
    BATaddress    = '0x0D8775F648430679A709E98d2b0Cb6250d2887EF';
    COMPaddress   = '0xc00e94Cb662C3520282E6f5717214004A7f26888';
    DAIaddress    = '0x6B175474E89094C44Da98b954EedeAC495271d0F';
    LINKaddress   = '0x514910771AF9Ca656af840dff83E8264EcF986CA';
    MKRaddress    = '0x9f8F72aA9304c8B593d555F12eF6589cC3A579A2';
    SUSHIaddress  = '0x6B3595068778DD592e39A122f4f5a5cF09C90fE2';
    TUSDaddress   = '0x0000000000085d4780B73119b644AE5ecd22b376';
    UNIaddress    = '0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984';
    USDCaddress   = '0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48';
    USDPaddress   = '0x8E870D67F660D95d5be530380D0eC0bd388289E1';
    USDTaddress   = '0xdAC17F958D2ee523a2206206994597C13D831ec7';
    WBTCaddress   = '0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599';
    YFIaddress    = '0x0bc529c00C6401aEF6D220BE8C6Ea1667F6Ad93e';
    ZRXaddress    = '0xE41d2489571d322189246DaFA5ebDe1F4699F498';
    cAAVEaddress  = '0xe65cdb6479bac1e22340e4e755fae7e509ecd06c';
    cBATaddress   = '0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E';
    cCOMPaddress  = '0x70e36f6bf80a52b3b46b3af8e106cc0ed743e8e4';
    cDAIaddress   = '0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643';
    cETHaddress   = '0x4ddc2d193948926d02f9b1fe9e1daa0718270ed5';
    cLINKaddress  = '0xface851a4921ce59e912d19329929ce6da6eb0c7';
    cMKRaddress   = '0x95b4ef2869ebd94beb4eee400a99824bf5dc325b';
    cSUSHIaddress = '0x4b0181102a0112a2ef11abee5563bb4a3176c9d7';
    cTUSDaddress  = '0x12392f67bdf24fae0af363c24ac620a2f67dad86';
    cUNIaddress   = '0x35a18000230da775cac24873d00ff85bccded550';
    cUSDCaddress  = '0x39aa39c021dfbae8fac545936693ac917d5e7563';
    cUSDPaddress  = '0x041171993284df560249b57358f931d9eb7b925d';
    cUSDTaddress  = '0xf650c3d88d12db855b8bf7d11be6c55a4e07dcc9';
    cWBTC2address = '0xccf4429db6322d5c611ee964527d42e5d685dd6a';
    cYFIaddress   = '0x80a2ae356fc9ef4305676f7a3e2ed04e12c33946';
    cZRXaddress   = '0xb3319f5d18bc0d84dd1b4825dcde5d5f7266d407';

    // ATC: I think this was the problem: signer was not aligned with address
    //[signer] = await ethers.getSigners();

    // ATC: Grab an address that holds BAT, DAI, and ETH
    // signerAddress = await signer.getAddress();
    signerAddress = '0x51399B32CD0186bB32230e24167489f3B2F47870';
    console.log(`Signer address is ${signerAddress}`);

    await hre.network.provider.request({
      method: 'hardhat_impersonateAccount',
      params: [signerAddress]
    });

    signer = await ethers.provider.getSigner(signerAddress);
    cBAT = new Contract(cBATaddress, CBAT_ABI, signer);
    cMKR = new Contract(cMKRaddress, CMKR_ABI, signer);
    cETH = new Contract(cETHaddress, CETH_ABI, signer);
    bridgeProxy = await DefiBridgeProxy.deploy(signer);
    CompoundBridgeAddress = await bridgeProxy.deployBridge(signer, abi, []);
 
    await signer.sendTransaction({
      to: bridgeProxy.address,
      value: parseEther('0.8')
    });
  });
 
  it('should supply BAT to Compound and get back cBAT', async () => {
    // Call convert to supply tokens to Compound and return cTokens to user.

    BAT = new Contract(BATaddress, ERC20_ABI, signer);

    // ATC: check signer's BAT balance here - this is correct
    signerERC20balance = (await BAT.balanceOf(signerAddress));
    console.log(`Signer BAT balance before transfer is ${signerERC20balance}`);

    // ATC: prepare to deposit 99999999e-18 BAT to the contract
    const depositERC20 = '99999999';
    console.log(`Depositing ${depositERC20} BAT`);
    const depositERC20value = 99999999n;

    // ATC: transfer BAT to the bridge manually
    await BAT.approve(CompoundBridgeAddress,signerERC20balance);
    await BAT.approve(cBATaddress,signerERC20balance);
    const BATallowance = (await BAT.allowance(signerAddress,CompoundBridgeAddress));
    console.log(`Bridge BAT allowance is ${BATallowance}`);
    await BAT.transfer(CompoundBridgeAddress,depositERC20value);
    signerERC20balance = (await BAT.balanceOf(signerAddress));
    console.log(`Signer BAT balance after transfer is ${signerERC20balance}`);
    bridgeERC20balance = (await BAT.balanceOf(CompoundBridgeAddress));
    console.log(`Bridge BAT balance after transfer is ${bridgeERC20balance}`);

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
      depositERC20value,
      1n,
      0n
    );

    const proxyBalance = BigInt((await cBAT.balanceOf(bridgeProxy.address)).toString());
    console.log(`Received ${proxyBalance} cBAT tokens`);
    console.log(`Error code from cBAT.mint() is ${outputValueB}`);
    expect(proxyBalance).toBe(outputValueA);
    //expect(outputValueB).toBe(0n);
    expect(isAsync).toBe(false);
  });

  it('should supply DAI to Compound and get back cDAI', async () => {
    // Call convert to supply tokens to Compound and return cTokens to user.

    DAI = new Contract(DAIaddress, ERC20_ABI, signer);

    // ATC: check signer's DAI balance here - this is correct
    signerERC20balance = (await DAI.balanceOf(signerAddress));
    console.log(`Signer DAI balance before transfer is ${signerERC20balance}`);

    // ATC: prepare to deposit 99999999e-18 DAI to the contract
    const depositERC20 = '99999999';
    console.log(`Depositing ${depositERC20} DAI`);
    const depositERC20value = 99999999n;

    // ATC: transfer DAI to the bridge manually
    await DAI.approve(CompoundBridgeAddress,signerERC20balance);
    await DAI.approve(cDAIaddress,signerERC20balance);
    const DAIallowance = (await DAI.allowance(signerAddress,CompoundBridgeAddress));
    console.log(`Bridge DAI allowance is ${DAIallowance}`);
    await DAI.transfer(CompoundBridgeAddress,depositERC20value);
    signerERC20balance = (await DAI.balanceOf(signerAddress));
    console.log(`Signer DAI balance after transfer is ${signerERC20balance}`);
    bridgeERC20balance = (await DAI.balanceOf(CompoundBridgeAddress));
    console.log(`Bridge DAI balance after transfer is ${bridgeERC20balance}`);

    const { isAsync, outputValueA, outputValueB } = await bridgeProxy.convert(
      signer,
      CompoundBridgeAddress,
      {
        assetType: AztecAssetType.ERC20,
        id: 0,
        erc20Address: DAIaddress
      },
      {},
      {
        assetType: AztecAssetType.ERC20,
        id: 1,
        erc20Address: cDAIaddress
      },
      {},
      depositERC20value,
      1n,
      0n
    );

    const proxyBalance = BigInt((await cDAI.balanceOf(bridgeProxy.address)).toString());
    console.log(`Received ${proxyBalance} cDAI tokens`);
    console.log(`Error code from cDAI.mint() is ${outputValueB}`);
    expect(proxyBalance).toBe(outputValueA);
    //expect(outputValueB).toBe(0n);
    expect(isAsync).toBe(false);
  });

  it('should supply ETH to Compound and return cETH', async () => {
    // Call convert to supply tokens to Compound and return cTokens to user.

    const depositETH = '0.12'
    console.log(`Depositing ${depositETH} ETH`);
    const { isAsync, outputValueA, outputValueB } = await bridgeProxy.convert(
      signer,
      CompoundBridgeAddress,
      {
        assetType: AztecAssetType.ETH,
        id: 0
      },
      {},
      {
        assetType: AztecAssetType.ERC20,
        id: 1,
        erc20Address: cETHaddress
      },
      {},
      BigInt(parseEther(depositETH).toString()),
      1n,
      0n
    );

    console.log(`Output cETH ${formatEther(outputValueA)}`);

    // Check cETH balance of bridge proxy
    const proxyBalance = BigInt((await cETH.balanceOf(bridgeProxy.address)).toString());
    console.log(`Received ${proxyBalance} cETH tokens`);
    // expect(proxyBalance).toBe(outputValueA);
    expect(outputValueB).toBe(0n);
    expect(isAsync).toBe(false);
  });
});
