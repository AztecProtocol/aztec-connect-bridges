import { ethers } from "hardhat";
import DefiBridgeProxy from "../../../../src/artifacts/contracts/DefiBridgeProxy.sol/DefiBridgeProxy.json";
import { Contract, Signer, ContractFactory } from "ethers";
import {
  TestToken,
  AztecAssetType,
  AztecAsset,
  RollupProcessor,
} from "../../../../src/rollup_processor";

import type { AaveLendingBridge } from "../../../../typechain-types";

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
  let aaveBridgeContract: AaveLendingBridge;

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
    const aaveFactory = await ethers.getContractFactory("AaveLendingBridge");
    aaveBridgeContract = await aaveFactory.deploy(
      rollupContract.address,
      aaveAddressProvider
    );
    await aaveBridgeContract.deployed();
  });

  it("should allow us to configure a new underlying to zkAToken mapping", async () => {
    const txResponse = await aaveBridgeContract
      .setUnderlyingToZkAToken(daiAddress)
      .catch(fixEthersStackTrace);
    await txResponse.wait();

    const zkAToken = await aaveBridgeContract.underlyingToZkAToken(daiAddress);
    expect(zkAToken).toBeDefined;
  });

  it("should not allow us to configure a new zkAToken if the underlying exists ", async () => {
    const addDai = async () => {
      return await aaveBridgeContract.setUnderlyingToZkAToken(daiAddress);
    };
    const txResponse = await addDai();
    await txResponse.wait();
    const zkAToken = await aaveBridgeContract.underlyingToZkAToken(daiAddress);
    expect(zkAToken).toBeDefined;
    await expect(addDai()).rejects.toThrow("AaveLendingBridge: ZK_TOKEN_SET");
    const zkAToken2 = await aaveBridgeContract.underlyingToZkAToken(daiAddress);
    expect(zkAToken).toBe(zkAToken2);
  });
});
