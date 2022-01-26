import { ethers } from "hardhat";
import DefiBridgeProxy from "../../../../src/artifacts/contracts/DefiBridgeProxy.sol/DefiBridgeProxy.json";
import AAVELendingBridge from "../../../../src/artifacts/contracts/bridges/AAVE/AAVELending.sol/AaveLendingBridge.json";
import { Contract, Signer, ContractFactory } from "ethers";
import {
  TestToken,
  AztecAssetType,
  AztecAsset,
  RollupProcessor,
} from "../../../../src/rollup_processor";
import { AaveBridge } from "../aave_bridge";

import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import { randomBytes } from "crypto";

const fixEthersStackTrace = (err: Error) => {
  err.stack! += new Error().stack;
  throw err;
};

describe("defi bridge", function () {
  let rollupContract: RollupProcessor;
  let aaveBridgeAddress: string;
  let defiBridgeProxy: Contract;

  const daiAddress = "0x6b175474e89094c44da98b954eedeac495271d0f";
  const aaveAddressProvider = "0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5";

  let signer: Signer;
  let aaveBridge: AaveBridge;
  let aaveBridgeContract: Contract;

  const randomAddress = () => randomBytes(20).toString("hex");

  beforeAll(async () => {
    [signer] = await ethers.getSigners();

    const factory = new ContractFactory(
      DefiBridgeProxy.abi,
      DefiBridgeProxy.bytecode,
      signer
    );
    defiBridgeProxy = await factory.deploy([]);
    rollupContract = await RollupProcessor.deploy(signer, [
      defiBridgeProxy.address,
    ]);
  });

  beforeEach(async () => {
    // deploy the bridge and pass in any args
    const args = [rollupContract.address, aaveAddressProvider];
    aaveBridge = await AaveBridge.deploy(signer, args);
    aaveBridgeContract = new Contract(
      aaveBridge.address,
      AAVELendingBridge.abi,
      signer
    );
  });

  it("should allow us to configure a new zkAToken ", async () => {
    const func = async () => {
      const txResponse = await aaveBridge
        .setUnderlyingToZkAToken(signer, daiAddress)
        .catch(fixEthersStackTrace);
      await txResponse.wait();
    };
    await expect(func()).resolves.toBe(undefined);
  });
});
