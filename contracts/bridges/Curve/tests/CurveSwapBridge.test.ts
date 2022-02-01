import chai, { expect } from "chai";
import { solidity } from "ethereum-waffle";
import hre, { ethers } from "hardhat";
import { CurveSwapBridge } from "../../../../typechain-types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { AztecAssetType } from "./aztec";
import * as mainnet from "./mainnet";
import { tokenPairs, fundERC20FromAccount} from "./helpers";

import { RollupProcessor } from "../../../../src/rollup_processor";

chai.use(solidity);

const SWAP_AMOUNT = "100";

const SWAPS = [
  ["WBTC", "WETH", "USDT"], // tricrypto
  ["USDC", "DAI", "USDT"], // 3crv
  ["UST", "USDC"], // UST+3crv
  ["UST", "USDT"], // UST+3crv
  ["UST", "DAI"], // UST+3crv
  ["MIM", "USDC"], // MIM+3crv
  ["MIM", "USDT"], // MIM+3crv
  ["MIM", "DAI"], // MIM+3crv
];

describe("CurveSwapBridge", function () {
  let bridge: CurveSwapBridge;
  let rollupContract: RollupProcessor;
  let signer: SignerWithAddress;
  let snapshotId: number;


  beforeAll(async () => {
    [signer] = await ethers.getSigners();

    const f = await ethers.getContractFactory("DefiBridgeProxy");
    const defiBridgeProxy = await f.deploy();
    await defiBridgeProxy.deployed();

    rollupContract = await RollupProcessor.deploy(signer, [
      defiBridgeProxy.address,
    ]);

    const Bridge = await ethers.getContractFactory("CurveSwapBridge");
    bridge = (await Bridge.deploy(
      rollupContract.address,
      mainnet.CURVE_ADDRESS_PROVIDER,
      mainnet.tokens.WETH.address
    )) as CurveSwapBridge;
    await bridge.deployed();

    snapshotId = (await hre.network.provider.request({
      method: "evm_snapshot",
      params: [],
    })) as number;
  });

  beforeEach(async () => {
    await hre.network.provider.request({
      method: "evm_revert",
      params: [snapshotId],
    });
  });

  for (const [token1, token2] of tokenPairs(SWAPS)) {
    it(`should swap ${token1.name} -> ${token2.name}`, async () => {
      const token1Contract = await ethers.getContractAt(
        "ERC20",
        token1.address
      );
      const token2Contract = await ethers.getContractAt(
        "ERC20",
        token2.address
      );

      const amount = ethers.utils.parseUnits(
        SWAP_AMOUNT,
        await token1Contract.decimals()
      );

      await fundERC20FromAccount(
        token1Contract,
        token1.holder,
        rollupContract.address,
        amount
      );

      // await rollupContract.preFundContractWithToken(signer, {
      //   name: token1.name,
      //   erc20Address: token1.address,
      //   amount: amount,
      // });

      const token1OrigBalance = await token1Contract.balanceOf(
        rollupContract.address
      );
      const token2OrigBalance = await token2Contract.balanceOf(
        rollupContract.address
      );

      const { isAsync, outputValueA, outputValueB } =
        await rollupContract.convert(
          signer,
          bridge.address,
          {
            id: 0,
            erc20Address: token1.address,
            assetType: AztecAssetType.ERC20,
          },
          {
            id: 0,
            erc20Address: ethers.constants.AddressZero,
            assetType: 0,
          },
          {
            id: 1,
            erc20Address: token2.address,
            assetType: AztecAssetType.ERC20,
          },
          {
            id: 0,
            erc20Address: ethers.constants.AddressZero,
            assetType: 0,
          },
          amount.toBigInt(),
          1n,
          0n
        );
      expect(outputValueB).to.equal(0n);
      expect(isAsync).to.be.false;

      const token2NewBalance = await token2Contract.balanceOf(
        rollupContract.address
      );
      expect(token2NewBalance).to.equal(token2OrigBalance.add(outputValueA));

      const token1NewBalance = await token1Contract.balanceOf(
        rollupContract.address
      );
      expect(token1NewBalance).to.equal(token1OrigBalance.sub(amount));
    });
  }
});
