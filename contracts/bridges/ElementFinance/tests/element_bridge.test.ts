import { ethers } from "hardhat";
import abi from "../../../../src/artifacts/contracts/bridges/ElementFinance/ElementBridge.sol/ElementBridge.json";
import { Contract, Signer } from "ethers";
import {
  DefiBridgeProxy,
  MyToken,
  AztecAssetType,
} from "../../../../src/defi_bridge_proxy";

describe("defi bridge", function () {
  let rollupContract: DefiBridgeProxy;
  let elementBridgeAddress: string;
  let signer: Signer;
  let signerAddress: string;
  let erc20: Contract;

  beforeAll(async () => {
    [signer] = await ethers.getSigners();
    signerAddress = await signer.getAddress();

    rollupContract = await DefiBridgeProxy.deploy(signer);
    // deploy the bridge and pass in any args
    //const byteCodeHash = Buffer.from("0xcfec87c9f5ec81c255ee6985e454f5ab0faeb0434fea9ab9b6db83ffab74d534", 'hex');
    const byteCodeHash = Buffer.from(
      "0xf9a3a5f11360d59f975ee3b3a133cea72978503c3940d56d12f7abdb16d42d52",
      "hex"
    );
    elementBridgeAddress = await rollupContract.deployBridge(signer, abi, [
      rollupContract.address,
      "0x62F161BF3692E4015BefB05A03a94A40f520d1c0",
      byteCodeHash,
    ]);
  });

  it("should take DAI and swap for ePyDAI vai the bridge for the given expiry in the aux data", async () => {
    // DAI Mainnet address
    const daiAddress = "0x6b175474e89094c44da98b954eedeac495271d0f";
    const totalInputValue = 1n * 10n ** 18n;

    const requiredTokens = [
      { erc20Address: daiAddress, amount: totalInputValue } as MyToken,
    ];
    await rollupContract.preFundRollupWithTokens(signer, requiredTokens);

    const { isAsync, outputValueA, outputValueB } =
      await rollupContract.convert(
        signer,
        elementBridgeAddress,
        {
          assetType: AztecAssetType.ERC20,
          id: 0,
          erc20Address: daiAddress,
        },
        {},
        {
          assetType: AztecAssetType.ERC20,
          id: 1,
          erc20Address: daiAddress,
        },
        {},
        1000n,
        1n,
        0n
      );

    // TODO check the bridge has deposited total input value to the balancer pool.
    // expect(balancerPool).toBe(totalInputValue);
    expect(outputValueA).toBe(0n);
    expect(outputValueB).toBe(0n);
    expect(isAsync).toBe(true);
  });
});
