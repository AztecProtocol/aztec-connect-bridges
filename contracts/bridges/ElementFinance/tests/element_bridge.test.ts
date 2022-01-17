import { ethers } from "hardhat";

import abi from "../../../../src/artifacts/contracts/bridges/ElementFinance/ElementBridge.sol/ElementBridge.json";

import { Contract, Signer } from "ethers";
import { DefiBridgeProxy, Token } from "../../../../src/defi_bridge_proxy";

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
    // elementBridgeAddress = await rollupContract.deployBridge(signer, abi, []);

    // Bridge proxy can be thought of as the rollup contract. Fund it.
    // TODO: Do for tokens.
    // await signer.sendTransaction({
    //   to: rollupContract.address,
    //   value: 10000n,
    // });
  });

  it("should take DAI and swap for ePyDAI vai the bridge for the given expiry in the aux data", async () => {
    // DAI Mainnet address
    const asset = "0x6b175474e89094c44da98b954eedeac495271d0f";
    const totalInputValue = 1;

    const requiredTokens = [
      { erc20Address: asset, amount: totalInputValue } as Token,
    ];
    await rollupContract.preFundRollupWithTokens(signer, requiredTokens);

    // const { isAsync, outputValueA, outputValueB } = await rollupContract.simulateBridgeInteraction(
    //   requiredTokens,
    //   signer,
    //   elementBridgeAddress,
    //   {
    //     assetType: AztecAssetType.ERC20,
    //     id: 0,
    //     erc20Address: "Dai Addresss",
    //   },
    //   {},
    //   {
    //     assetType: AztecAssetType.ERC20,
    //     id: 1,
    //     erc20Address: erc20.address,
    //   },
    //   {},
    //   1000n,
    //   1n,
    //   0n
    // );

    // const proxyBalance = BigInt(
    //   (await erc20.balanceOf(bridgeProxy.address)).toString()
    // );
    // expect(proxyBalance).toBe(outputValueA);
    // expect(outputValueB).toBe(0n);
    // expect(isAsync).toBe(false);
  });
});
