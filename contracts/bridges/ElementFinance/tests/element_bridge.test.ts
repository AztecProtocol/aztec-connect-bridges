import { ethers, config as hardhatConfig, network as hardhatNetwork } from "hardhat";
import DefiBridgeProxy from "../../../../src/artifacts/contracts/DefiBridgeProxy.sol/DefiBridgeProxy.json";
import { Contract, Signer, ContractFactory } from "ethers";
import {
  AztecAssetType,
  AztecAsset,
} from "../../../../src/utils";
import { RollupProcessor } from "../../../../src/rollup_processor";
import { ElementBridge } from "../../../../src/element_bridge";
import ERC20 from "@openzeppelin/contracts/build/contracts/ERC20.json";
import { randomBytes } from "crypto";
import * as VaultConfig from "./VaultConfig.json";

const REQUIRED_BLOCK = 14000001;

const fixEthersStackTrace = (err: Error) => {
  err.stack! += new Error().stack;
  throw err;
};

const getCurrentBlockTime = async () => {
  const blockNumBefore = await ethers.provider.getBlockNumber();
  const blockBefore = await ethers.provider.getBlock(blockNumBefore);
  return blockBefore.timestamp;
};

const setBlockchainTime = async (timestamp: number) => {
  const blockTimestamp = await getCurrentBlockTime();
  await ethers.provider.send("evm_increaseTime", [
    timestamp - blockTimestamp,
  ]);
  await ethers.provider.send("evm_mine", []);
};

const ensureCorrectBlock = async (expectedBlock: number) => {
  const blockNumber = await ethers.provider.getBlockNumber();
  expect(blockNumber).toEqual(expectedBlock);
};

const resetBlock = async () => {
  try{
    await hardhatNetwork.provider.request({
      method: "hardhat_reset",
      params: [
        {
          forking: {
            jsonRpcUrl: hardhatConfig.networks.hardhat.forking!.url!,
            blockNumber: hardhatConfig.networks.hardhat.forking!.blockNumber!
          },
        },
      ],
    });
  } catch(e) {
    console.log("Failed to reset hardhat", e);
  }
}

interface SwapQuantities {
  trancheBridge: bigint;
  trancheBalancer: bigint;
  underlyingRollup: bigint;
  underlyingBalancer: bigint;
}

interface ElementPoolSpec {
  underlyingAddress: string;
  wrappedPositionAddress: string;
  poolAddress: string;
  expiry: number;
  trancheAddress: string;
  name: string;
}

interface AssetSpec {
  decimals: bigint;
  quantityExponent: bigint;
  disabled: boolean;
}

interface AssetSpecs {
  specs: Map<string, AssetSpec>;
}

function buildPoolSpecs(asset: string, config: any): ElementPoolSpec[] {
  const tranches = config.tranches[asset];
  if (!tranches) {
    return [];
  }
  return tranches.map((tranche: any) => {
    const spec = {
      underlyingAddress: config.tokens[asset],
      wrappedPositionAddress: config.wrappedPositions.yearn[asset],
      poolAddress: tranche.ptPool.address,
      expiry: tranche.expiration,
      trancheAddress: tranche.address,
      name: asset,
    } as ElementPoolSpec;
    return spec;
  });
}

const assetSpecs: AssetSpecs = {
  specs: new Map<string, AssetSpec>([
    [
      "usdc",
      {
        decimals: 6n,
        quantityExponent: 6n,
        disabled: false,
      },
    ], // working
    [
      "weth", // no tranches
      {
        decimals: 18n,
        quantityExponent: 18n,
        disabled: true,
      },
    ],
    [
      "dai",
      {
        decimals: 18n,
        quantityExponent: 18n,
        disabled: false,
      },
    ],
    [
      "lusd3crv-f",
      {
        decimals: 18n,
        quantityExponent: 9n,
        disabled: false,
      },
    ],
    [
      "crvtricrypto", // expiry too old
      {
        decimals: 18n,
        quantityExponent: 18n,
        disabled: true,
      },
    ],
    [
      "stecrv",
      {
        decimals: 18n,
        quantityExponent: 6n,
        disabled: false,
      },
    ],
    [
      "crv3crypto", // doesn't seem to have a pool associated with it
      {
        decimals: 18n,
        quantityExponent: 18n,
        disabled: true,
      },
    ],
    [
      "wbtc",
      {
        decimals: 8n,
        quantityExponent: 5n,
        disabled: true,
      },
    ],
    [
      "alusd3crv-f",
      {
        decimals: 18n,
        quantityExponent: 18n,
        disabled: false,
      },
    ],
    [
      "mim-3lp3crv-f",
      {
        decimals: 18n,
        quantityExponent: 18n,
        disabled: false,
      },
    ],
    [
      "eurscrv", // needs EURS which we can't seem to get on uniswap
      {
        decimals: 18n,
        quantityExponent: 18n,
        disabled: true,
      },
    ],
  ]),
};

const getBalances = async (
  trancheAddress: string,
  underlyingAddress: string,
  signer: Signer,
  balancerAddress: string,
  bridgeAddress: string,
  rollupAddress: string
) => {
  const trancheTokenContract = new Contract(trancheAddress, ERC20.abi, signer);

  const underlyingContract = new Contract(underlyingAddress, ERC20.abi, signer);

  const quantities = {
    underlyingBalancer: BigInt(
      await underlyingContract.balanceOf(balancerAddress)
    ),
    underlyingRollup: BigInt(await underlyingContract.balanceOf(rollupAddress)),
    trancheBalancer: BigInt(
      await trancheTokenContract.balanceOf(balancerAddress)
    ),
    trancheBridge: BigInt(await trancheTokenContract.balanceOf(bridgeAddress)),
  } as SwapQuantities;
  return {
    quantities: quantities,
  };
};

const checkBalances = (
  beforeConvert: SwapQuantities,
  afterConvert: SwapQuantities,
  beforeFinalise: SwapQuantities,
  afterFinalise: SwapQuantities
) => {
  const changeInRollupUnderlyingOnConvert =
    afterConvert.underlyingRollup - beforeConvert.underlyingRollup;
  const changeInBalancerUnderlyingOnConvert =
    afterConvert.underlyingBalancer - beforeConvert.underlyingBalancer;
  const changeInBridgeTrancheOnConvert =
    afterConvert.trancheBridge - beforeConvert.trancheBridge;
  const changeInBalancerTrancheOnConvert =
    afterConvert.trancheBalancer - beforeConvert.trancheBalancer;
  expect(changeInRollupUnderlyingOnConvert).toEqual(
    changeInBalancerUnderlyingOnConvert * -1n
  );
  expect(changeInBridgeTrancheOnConvert).toEqual(
    changeInBalancerTrancheOnConvert * -1n
  );
  expect(changeInBridgeTrancheOnConvert).toBeGreaterThan(
    changeInBalancerUnderlyingOnConvert
  );

  const changeInRollupUnderlyingOnFinalise =
    afterFinalise.underlyingRollup - beforeFinalise.underlyingRollup;
  const changeInBridgeTrancheOnFinalise =
    afterFinalise.trancheBridge - beforeFinalise.trancheBridge;
  expect(changeInBridgeTrancheOnFinalise).toBe(
    changeInBridgeTrancheOnConvert * -1n
  );
  expect(changeInRollupUnderlyingOnFinalise).toBeGreaterThan(
    changeInRollupUnderlyingOnConvert * -1n
  );
};

interface Interaction {
  amount: bigint;
  spec: ElementPoolSpec;
  nonce: bigint;
  gasUsedConvert: bigint;
  gasUsedFinalise: bigint;
  finalised: boolean;
  beforeConvert: SwapQuantities;
  afterConvert: SwapQuantities;
  beforefinalise?: SwapQuantities;
  afterFinalise?: SwapQuantities;
  finalisedNonce?: bigint;
}

const logInteractions = (interactions: Interaction[], prefix: string) => {
  const interactionsCopy = [...interactions];
  while (interactionsCopy.length) {
    const interactionsToLog = interactionsCopy.splice(0, 50);
    const gasUsage = interactionsToLog.flatMap((interaction) => {
      const nonceFinalised = interaction.finalisedNonce == undefined ? '' : `, nonce finalised: ${interaction.finalisedNonce}`;
      return `Interaction ${interaction.nonce}, asset ${
        interaction.spec.name
      }, expiry ${new Date(interaction.spec.expiry * 1000)}, gas to convert: ${
        interaction.gasUsedConvert
      }, gas to finalise: ${interaction.gasUsedFinalise}${nonceFinalised}`;
    });
    console.log([prefix, ...gasUsage]);
  }
}

jest.setTimeout(6000000);

describe("defi bridge", function () {
  const vaultConfig = VaultConfig;
  let rollupContract: RollupProcessor;
  let defiBridgeProxy: Contract;
  let elementBridge: ElementBridge;
  const balancerAddress = "0xBA12222222228d8Ba445958a75a0704d566BF2C8";
  const daiAddress = "0x6b175474e89094c44da98b954eedeac495271d0f";
  const byteCodeHash = Buffer.from(
    "f481a073666136ab1f5e93b296e84df58092065256d0db23b2d22b62c68e978d",
    "hex"
  );
  const trancheFactoryAddress = "0x62F161BF3692E4015BefB05A03a94A40f520d1c0";
  let signer: Signer;

  const elementDaiWrappedPositionAddress =
    "0x21BbC083362022aB8D7e42C18c47D484cc95C193";

  const elementDaiApr2022Spec = {
    underlyingAddress: daiAddress,
    wrappedPositionAddress: elementDaiWrappedPositionAddress,
    poolAddress: "0xEdf085f65b4F6c155e13155502Ef925c9a756003",
    trancheAddress: "0x2c72692e94e757679289ac85d3556b2c0f717e0e",
    expiry: 1651275535,
  } as ElementPoolSpec;

  const elementDaiJan2022Spec = {
    underlyingAddress: daiAddress,
    wrappedPositionAddress: elementDaiWrappedPositionAddress,
    poolAddress: "0xA47D1251CF21AD42685Cc6B8B3a186a73Dbd06cf",
    trancheAddress: "0x449d7c2e096e9f867339078535b15440d42f78e8",
    expiry: 1643382446,
  } as ElementPoolSpec;

  const randomAddress = () => randomBytes(20).toString("hex");

  beforeEach(async () => {
    [signer] = await ethers.getSigners();
    await resetBlock();
    ensureCorrectBlock(REQUIRED_BLOCK);
    const factory = new ContractFactory(
      DefiBridgeProxy.abi,
      DefiBridgeProxy.bytecode,
      signer
    );
    defiBridgeProxy = await factory.deploy([]);
    rollupContract = await RollupProcessor.deploy(signer, [
      defiBridgeProxy.address,
    ]);
    // deploy the bridge and pass in any args
    const args = [
      rollupContract.address,
      trancheFactoryAddress,
      byteCodeHash,
      balancerAddress,
    ];
    elementBridge = await ElementBridge.deploy(signer, args);
  });

  it("should allow us to configure a new pool", async () => {
    const func = async () => {
      await elementBridge
        .registerConvergentPoolAddress(
          signer,
          elementDaiApr2022Spec.poolAddress,
          elementDaiApr2022Spec.wrappedPositionAddress,
          elementDaiApr2022Spec.expiry
        )
        .catch(fixEthersStackTrace);
    };
    await expect(func()).resolves.toBe(undefined);
  });

  it("should allow us to configure the same pool multiple times", async () => {
    const func = async () => {
      await elementBridge.registerConvergentPoolAddress(
        signer,
        elementDaiApr2022Spec.poolAddress,
        elementDaiApr2022Spec.wrappedPositionAddress,
        elementDaiApr2022Spec.expiry
      );

      await elementBridge.registerConvergentPoolAddress(
        signer,
        elementDaiApr2022Spec.poolAddress,
        elementDaiApr2022Spec.wrappedPositionAddress,
        elementDaiApr2022Spec.expiry
      );

      await elementBridge.registerConvergentPoolAddress(
        signer,
        elementDaiApr2022Spec.poolAddress,
        elementDaiApr2022Spec.wrappedPositionAddress,
        elementDaiApr2022Spec.expiry
      );
    };
    await expect(func()).resolves.not.toThrow();
  });

  it("should allow us to configure multiple pools", async () => {
    const func = async () => {
      await elementBridge.registerConvergentPoolAddress(
        signer,
        elementDaiApr2022Spec.poolAddress,
        elementDaiApr2022Spec.wrappedPositionAddress,
        elementDaiApr2022Spec.expiry
      );

      await elementBridge.registerConvergentPoolAddress(
        signer,
        elementDaiJan2022Spec.poolAddress,
        elementDaiJan2022Spec.wrappedPositionAddress,
        elementDaiJan2022Spec.expiry
      );
    };
    await expect(func()).resolves.not.toThrow();
  });

  it("should not allow us to configure wrong expiry", async () => {
    // wrong expiry
    const wrongExpiry = async () => {
      await elementBridge.registerConvergentPoolAddress(
        signer,
        elementDaiApr2022Spec.poolAddress,
        elementDaiApr2022Spec.wrappedPositionAddress,
        elementDaiJan2022Spec.expiry
      );
    };
    await expect(wrongExpiry()).rejects.toThrow("POOL_EXPIRY_MISMATCH");
  });

  it("should not allow us to configure wrong wrapped position", async () => {
    //invalid wrapped position
    const wrongPosition = async () => {
      await elementBridge.registerConvergentPoolAddress(
        signer,
        elementDaiApr2022Spec.poolAddress,
        randomAddress(),
        elementDaiApr2022Spec.expiry
      );
    };
    await expect(wrongPosition()).rejects.toThrow();
  });

  it("should not allow us to configure wrong pool", async () => {
    // // wrong pool
    const wrongPool = async () => {
      await elementBridge.registerConvergentPoolAddress(
        signer,
        elementDaiJan2022Spec.poolAddress,
        elementDaiApr2022Spec.wrappedPositionAddress,
        elementDaiApr2022Spec.expiry
      );
    };
    await expect(wrongPool()).rejects.toThrow("POOL_EXPIRY_MISMATCH");
  });

  it("should not allow us to configure invalid pool", async () => {
    // invalid pool
    const invalidPool = async () => {
      await elementBridge.registerConvergentPoolAddress(
        signer,
        randomAddress(),
        elementDaiApr2022Spec.wrappedPositionAddress,
        elementDaiApr2022Spec.expiry
      );
    };
    await expect(invalidPool()).rejects.toThrow();
  });

  it("should not allow conversion from non ERC20 assets", async () => {
    const inputAsset = {
      assetType: AztecAssetType.VIRTUAL,
      id: 1,
      erc20Address: daiAddress,
    } as AztecAsset;
    const outputAsset = inputAsset;
    const convertFunc = async () => {
      await rollupContract.convert(
        signer,
        elementBridge.address,
        inputAsset,
        {},
        outputAsset,
        {},
        1n,
        1n,
        BigInt(elementDaiApr2022Spec.expiry)
      );
    };
    await expect(convertFunc()).rejects.toThrow();
  });

  it("should not allow conversion from non ERC20 assets 2", async () => {
    const inputAsset = {
      assetType: AztecAssetType.ETH,
      id: 1,
      erc20Address: daiAddress,
    } as AztecAsset;
    const outputAsset = inputAsset;
    const convertFunc = async () => {
      await rollupContract.convert(
        signer,
        elementBridge.address,
        inputAsset,
        {},
        outputAsset,
        {},
        1n,
        1n,
        BigInt(elementDaiApr2022Spec.expiry)
      );
    };
    await expect(convertFunc()).rejects.toThrow();
  });

  it("should not allow conversion from non ERC20 assets 3", async () => {
    const inputAsset = {
      assetType: AztecAssetType.NOT_USED,
      id: 1,
      erc20Address: daiAddress,
    } as AztecAsset;
    const outputAsset = inputAsset;
    const convertFunc = async () => {
      await rollupContract.convert(
        signer,
        elementBridge.address,
        inputAsset,
        {},
        outputAsset,
        {},
        1n,
        1n,
        BigInt(elementDaiApr2022Spec.expiry)
      );
    };
    await expect(convertFunc()).rejects.toThrow();
  });

  it("should reject input and output assets being different", async () => {
    const inputAsset = {
      assetType: AztecAssetType.ERC20,
      id: 1,
      erc20Address: daiAddress,
    } as AztecAsset;
    const outputAsset = inputAsset;
    const convertFunc = async () => {
      await rollupContract.convert(
        signer,
        elementBridge.address,
        inputAsset,
        {},
        outputAsset,
        {},
        1n,
        1n,
        BigInt(elementDaiApr2022Spec.expiry)
      );
    };
    await expect(convertFunc()).rejects.toThrow();
  });

  it("should take DAI and swap for ePyDAI via the bridge for the given expiry in the aux data", async () => {
    const contractSpec = elementDaiApr2022Spec;

    const quantityOfDaiToDeposit = 1n * 10n ** 21n;
    const interactionNonce = 1n;
    // get 1 DAI into the rollup contract
    await rollupContract.preFundContractWithToken(signer, {
      erc20Address: contractSpec.underlyingAddress,
      amount: quantityOfDaiToDeposit,
      name: "dai",
    });

    const register = async () => {
      await elementBridge
        .registerConvergentPoolAddress(
          signer,
          contractSpec.poolAddress,
          contractSpec.wrappedPositionAddress,
          contractSpec.expiry
        )
        .catch(fixEthersStackTrace);
    };

    await expect(register()).resolves.not.toThrow();

    // measure the quantities of DAI and principal tokens in both the bridge contract and the balancer
    const underlyingContract = new Contract(
      contractSpec.underlyingAddress,
      ERC20.abi,
      signer
    );
    const trancheTokenContract = new Contract(
      contractSpec.trancheAddress,
      ERC20.abi,
      signer
    );

    const before = {
      trancheBalancer: BigInt(
        await underlyingContract.balanceOf(balancerAddress)
      ),
      trancheBridge: BigInt(
        await underlyingContract.balanceOf(elementBridge.address)
      ),
      underlyingBalancer: BigInt(
        await trancheTokenContract.balanceOf(balancerAddress)
      ),
      underlyingRollup: BigInt(
        await trancheTokenContract.balanceOf(elementBridge.address)
      ),
    } as SwapQuantities;

    // for the element bridge, input assets and output assets are the same
    const inputAsset = {
      assetType: AztecAssetType.ERC20,
      id: 1,
      erc20Address: contractSpec.underlyingAddress,
    } as AztecAsset;
    const outputAsset = inputAsset;

    const { results, gasUsed } =
      await rollupContract.convert(
        signer,
        elementBridge.address,
        inputAsset,
        {},
        outputAsset,
        {},
        quantityOfDaiToDeposit,
        interactionNonce,
        BigInt(contractSpec.expiry)
      );
    expect(results.length).toBe(1);
    expect(results[0].outputValueA).toBe(0n);
    expect(results[0].outputValueB).toBe(0n);
    expect(results[0].isAsync).toBe(true);

    const after = {
      trancheBalancer: BigInt(
        await underlyingContract.balanceOf(balancerAddress)
      ),
      trancheBridge: BigInt(
        await underlyingContract.balanceOf(elementBridge.address)
      ),
      underlyingBalancer: BigInt(
        await trancheTokenContract.balanceOf(balancerAddress)
      ),
      underlyingRollup: BigInt(
        await trancheTokenContract.balanceOf(elementBridge.address)
      ),
    } as SwapQuantities;

    // balancer should have our dai deposit
    expect(after.trancheBalancer).toEqual(
      before.trancheBalancer + quantityOfDaiToDeposit
    );
    // the increase of principal tokens in the bridge should be the same as the decrease in the balancer
    expect(before.underlyingBalancer - after.underlyingBalancer).toEqual(
      after.underlyingRollup - before.underlyingRollup
    );
    // no dai should be left in the bridge
    expect(after.trancheBridge).toEqual(0n);
  });

  it("should take DAI and swap for ePyDAI via the bridge for the given expiry in the aux data 2", async () => {
    const contractSpec = elementDaiJan2022Spec;

    const quantityOfDaiToDeposit = 1n * 10n ** 21n;
    const interactionNonce = 1n;
    // get 1 DAI into the rollup contract
    const daiAsset = assetSpecs.specs.get("dai")!;
    await rollupContract.preFundContractWithToken(signer, {
      erc20Address: contractSpec.underlyingAddress,
      amount: quantityOfDaiToDeposit,
      name: "dai",
    });

    const register = async () => {
      await elementBridge
        .registerConvergentPoolAddress(
          signer,
          contractSpec.poolAddress,
          contractSpec.wrappedPositionAddress,
          contractSpec.expiry
        )
        .catch(fixEthersStackTrace);
    };

    await expect(register()).resolves.not.toThrow();

    // measure the quantities of DAI and principal tokens in both the bridge contract and the balancer
    const underlyingContract = new Contract(
      contractSpec.underlyingAddress,
      ERC20.abi,
      signer
    );
    const trancheTokenContract = new Contract(
      contractSpec.trancheAddress,
      ERC20.abi,
      signer
    );

    const before = {
      trancheBalancer: BigInt(
        await underlyingContract.balanceOf(balancerAddress)
      ),
      trancheBridge: BigInt(
        await underlyingContract.balanceOf(elementBridge.address)
      ),
      underlyingBalancer: BigInt(
        await trancheTokenContract.balanceOf(balancerAddress)
      ),
      underlyingRollup: BigInt(
        await trancheTokenContract.balanceOf(elementBridge.address)
      ),
    } as SwapQuantities;

    // for the element bridge, input assets and output assets are the same
    const inputAsset = {
      assetType: AztecAssetType.ERC20,
      id: 1,
      erc20Address: contractSpec.underlyingAddress,
    } as AztecAsset;
    const outputAsset = inputAsset;

    const { results, gasUsed } =
      await rollupContract.convert(
        signer,
        elementBridge.address,
        inputAsset,
        {},
        outputAsset,
        {},
        quantityOfDaiToDeposit,
        interactionNonce,
        BigInt(contractSpec.expiry)
      );

      expect(results.length).toBe(1);
      expect(results[0].outputValueA).toBe(0n);
      expect(results[0].outputValueB).toBe(0n);
      expect(results[0].isAsync).toBe(true);

    const after = {
      trancheBalancer: BigInt(
        await underlyingContract.balanceOf(balancerAddress)
      ),
      trancheBridge: BigInt(
        await underlyingContract.balanceOf(elementBridge.address)
      ),
      underlyingBalancer: BigInt(
        await trancheTokenContract.balanceOf(balancerAddress)
      ),
      underlyingRollup: BigInt(
        await trancheTokenContract.balanceOf(elementBridge.address)
      ),
    } as SwapQuantities;

    // balancer should have our dai deposit
    expect(after.trancheBalancer).toEqual(
      before.trancheBalancer + quantityOfDaiToDeposit
    );
    // the increase of principal tokens in the bridge should be the same as the decrease in the balancer
    expect(before.underlyingBalancer - after.underlyingBalancer).toEqual(
      after.underlyingRollup - before.underlyingRollup
    );
    // no dai should be left in the bridge
    expect(after.trancheBridge).toEqual(0n);
  });

  it("should accept multiple deposits", async () => {
    const contractSpec = elementDaiJan2022Spec;

    const quantityOfDaiToDeposit = 1n * 10n ** 21n;
    // get 1 DAI into the rollup contract
    const daiAsset = assetSpecs.specs.get("dai")!;
    await rollupContract.preFundContractWithToken(signer, {
      erc20Address: contractSpec.underlyingAddress,
      amount: quantityOfDaiToDeposit,
      name: "dai",
    });

    const register = async () => {
      await elementBridge
        .registerConvergentPoolAddress(
          signer,
          contractSpec.poolAddress,
          contractSpec.wrappedPositionAddress,
          contractSpec.expiry
        )
        .catch(fixEthersStackTrace);
    };

    await expect(register()).resolves.not.toThrow();

    // measure the quantities of DAI and principal tokens in both the bridge contract and the balancer
    const underlyingContract = new Contract(
      contractSpec.underlyingAddress,
      ERC20.abi,
      signer
    );
    const trancheTokenContract = new Contract(
      contractSpec.trancheAddress,
      ERC20.abi,
      signer
    );

    const before = {
      trancheBalancer: BigInt(
        await underlyingContract.balanceOf(balancerAddress)
      ),
      trancheBridge: BigInt(
        await underlyingContract.balanceOf(elementBridge.address)
      ),
      underlyingBalancer: BigInt(
        await trancheTokenContract.balanceOf(balancerAddress)
      ),
      underlyingRollup: BigInt(
        await trancheTokenContract.balanceOf(elementBridge.address)
      ),
    } as SwapQuantities;

    // for the element bridge, input assets and output assets are the same
    const inputAsset = {
      assetType: AztecAssetType.ERC20,
      id: 1,
      erc20Address: contractSpec.underlyingAddress,
    } as AztecAsset;
    const outputAsset = inputAsset;

    let results = await rollupContract.convert(
      signer,
      elementBridge.address,
      inputAsset,
      {},
      outputAsset,
      {},
      quantityOfDaiToDeposit / 2n,
      1n,
      BigInt(contractSpec.expiry)
    );

    expect(results.results.length).toBe(1);
    expect(results.results[0].outputValueA).toBe(0n);
    expect(results.results[0].outputValueB).toBe(0n);
    expect(results.results[0].isAsync).toBe(true);

    // second deposit
    results = await rollupContract.convert(
      signer,
      elementBridge.address,
      inputAsset,
      {},
      outputAsset,
      {},
      quantityOfDaiToDeposit / 2n,
      2n,
      BigInt(contractSpec.expiry)
    );

    expect(results.results.length).toBe(1);
    expect(results.results[0].outputValueA).toBe(0n);
    expect(results.results[0].outputValueB).toBe(0n);
    expect(results.results[0].isAsync).toBe(true);

    const after = {
      trancheBalancer: BigInt(
        await underlyingContract.balanceOf(balancerAddress)
      ),
      trancheBridge: BigInt(
        await underlyingContract.balanceOf(elementBridge.address)
      ),
      underlyingBalancer: BigInt(
        await trancheTokenContract.balanceOf(balancerAddress)
      ),
      underlyingRollup: BigInt(
        await trancheTokenContract.balanceOf(elementBridge.address)
      ),
    } as SwapQuantities;

    // balancer should have our dai deposit
    expect(after.trancheBalancer).toEqual(
      before.trancheBalancer + quantityOfDaiToDeposit
    );
    // the increase of principal tokens in the bridge should be the same as the decrease in the balancer
    expect(before.underlyingBalancer - after.underlyingBalancer).toEqual(
      after.underlyingRollup - before.underlyingRollup
    );
    // no dai should be left in the bridge
    expect(after.trancheBridge).toEqual(0n);
  });

  it("should reject duplicate nonce", async () => {
    const contractSpec = elementDaiJan2022Spec;

    const quantityOfDaiToDeposit = 1n * 10n ** 21n;
    // get 1 DAI into the rollup contract
    await rollupContract.preFundContractWithToken(signer, {
      erc20Address: contractSpec.underlyingAddress,
      amount: quantityOfDaiToDeposit,
      name: "dai",
    });

    const register = async () => {
      await elementBridge
        .registerConvergentPoolAddress(
          signer,
          contractSpec.poolAddress,
          contractSpec.wrappedPositionAddress,
          contractSpec.expiry
        )
        .catch(fixEthersStackTrace);
    };

    await expect(register()).resolves.not.toThrow();

    // for the element bridge, input assets and output assets are the same
    const inputAsset = {
      assetType: AztecAssetType.ERC20,
      id: 1,
      erc20Address: contractSpec.underlyingAddress,
    } as AztecAsset;
    const outputAsset = inputAsset;

    const convert = async (nonce: bigint) => {
      await rollupContract.convert(
        signer,
        elementBridge.address,
        inputAsset,
        {},
        outputAsset,
        {},
        quantityOfDaiToDeposit / 2n,
        nonce,
        BigInt(contractSpec.expiry)
      );
    };

    await expect(convert(1n)).resolves.not.toThrow();
    // second call with same nonce should fail
    await expect(convert(1n)).rejects.toThrow("INTERACTION_ALREADY_EXISTS");
  });

  it("should inform that interaction is not ready to be finalised", async () => {
    const contractSpec = elementDaiApr2022Spec;

    const quantityOfDaiToDeposit = 1n * 10n ** 21n;
    const interactionNonce = 1n;
    // get 1 DAI into the rollup contract
    await rollupContract.preFundContractWithToken(signer, {
      erc20Address: contractSpec.underlyingAddress,
      amount: quantityOfDaiToDeposit,
      name: "dai",
    });

    const register = async () => {
      await elementBridge
        .registerConvergentPoolAddress(
          signer,
          contractSpec.poolAddress,
          contractSpec.wrappedPositionAddress,
          contractSpec.expiry
        )
        .catch(fixEthersStackTrace);
    };

    await expect(register()).resolves.not.toThrow();

    // for the element bridge, input assets and output assets are the same
    const inputAsset = {
      assetType: AztecAssetType.ERC20,
      id: 1,
      erc20Address: contractSpec.underlyingAddress,
    } as AztecAsset;
    const outputAsset = inputAsset;

    const results =
      await rollupContract.convert(
        signer,
        elementBridge.address,
        inputAsset,
        {},
        outputAsset,
        {},
        quantityOfDaiToDeposit,
        interactionNonce,
        BigInt(contractSpec.expiry)
      );

    expect(results.results.length).toBe(1);
    expect(results.results[0].outputValueA).toBe(0n);
    expect(results.results[0].outputValueB).toBe(0n);
    expect(results.results[0].isAsync).toBe(true);

    const canFinalise = await elementBridge.canFinalise(1n);
    expect(canFinalise).toEqual(false);
  });

  it("should reject can finalise on non-existent nonce", async () => {
    const finalise = async () => {
      await elementBridge.canFinalise(100n);
    };
    await expect(finalise()).rejects.toThrow("UNKNOWN_NONCE");
  });

  it("should reject finalise on non-existent nonce", async () => {
    const interactionNonce = 1n;

    const finalise = async () => {
      await rollupContract.processAsyncDefiInteraction(
        signer,
        interactionNonce
      );
    };
    await expect(finalise()).rejects.toThrow("UNKNOWN_NONCE");
  });

  it("should reject finalising interaction before it is ready", async () => {
    const contractSpec = elementDaiApr2022Spec;

    const quantityOfDaiToDeposit = 1n * 10n ** 21n;
    const interactionNonce = 1n;
    // get 1 DAI into the rollup contract
    await rollupContract.preFundContractWithToken(signer, {
      erc20Address: contractSpec.underlyingAddress,
      amount: quantityOfDaiToDeposit,
      name: "dai",
    });

    const register = async () => {
      await elementBridge
        .registerConvergentPoolAddress(
          signer,
          contractSpec.poolAddress,
          contractSpec.wrappedPositionAddress,
          contractSpec.expiry
        )
        .catch(fixEthersStackTrace);
    };

    await expect(register()).resolves.not.toThrow();

    // for the element bridge, input assets and output assets are the same
    const inputAsset = {
      assetType: AztecAssetType.ERC20,
      id: 1,
      erc20Address: contractSpec.underlyingAddress,
    } as AztecAsset;
    const outputAsset = inputAsset;

    const results =
      await rollupContract.convert(
        signer,
        elementBridge.address,
        inputAsset,
        {},
        outputAsset,
        {},
        quantityOfDaiToDeposit,
        interactionNonce,
        BigInt(contractSpec.expiry)
      );

    expect(results.results.length).toBe(1);
    expect(results.results[0].outputValueA).toBe(0n);
    expect(results.results[0].outputValueB).toBe(0n);
    expect(results.results[0].isAsync).toBe(true);

    const finalise = async () => {
      await rollupContract.processAsyncDefiInteraction(
        signer,
        interactionNonce
      );
    };
    await expect(finalise()).rejects.toThrow("BRIDGE_NOT_READY");
  });


  (Object.keys(vaultConfig.tokens).flatMap(x => {
    const assetSpec = assetSpecs.specs.get(x);
    if (!assetSpec || assetSpec.disabled) {
      return [];
    }
    return buildPoolSpecs(x, vaultConfig);
  })).forEach((poolSpec: ElementPoolSpec) => {
    it(`finalising interaction for ${poolSpec.name} - ${new Date(poolSpec.expiry * 1000)} should succeed once term is reached`, async () => {
      const contractSpec = poolSpec;
      const currentTimestamp = await getCurrentBlockTime();
      if (currentTimestamp >= poolSpec.expiry) {
        return;
      }
  
      const quantityExponent = assetSpecs.specs.get(poolSpec.name)!.quantityExponent;
      const quantityToDeposit = 1n * 10n ** quantityExponent;
      const interactionNonce = 68n;

      try {
        await rollupContract.preFundContractWithToken(signer, {
          erc20Address: contractSpec.underlyingAddress,
          amount: quantityToDeposit,
          name: poolSpec.name
        });
    
        const register = async () => {
          await elementBridge
            .registerConvergentPoolAddress(
              signer,
              contractSpec.poolAddress,
              contractSpec.wrappedPositionAddress,
              contractSpec.expiry
            )
            .catch(fixEthersStackTrace);
        };
    
        await register();
      } catch (e) {
        return;
      }
  
      // for the element bridge, input assets and output assets are the same
      const inputAsset = {
        assetType: AztecAssetType.ERC20,
        id: 1,
        erc20Address: contractSpec.underlyingAddress,
      } as AztecAsset;
      const outputAsset = inputAsset;
  
      const beforeConvert = await getBalances(
        contractSpec.trancheAddress,
        contractSpec.underlyingAddress,
        signer,
        balancerAddress,
        elementBridge.address,
        rollupContract.address
      );
  
      const results =
        await rollupContract.convert(
          signer,
          elementBridge.address,
          inputAsset,
          {},
          outputAsset,
          {},
          quantityToDeposit,
          interactionNonce,
          BigInt(contractSpec.expiry)
        );
  
      const afterConvert = await getBalances(
        contractSpec.trancheAddress,
        contractSpec.underlyingAddress,
        signer,
        balancerAddress,
        elementBridge.address,
        rollupContract.address
      );
  
      expect(results.results.length).toBe(1);
      expect(results.results[0].outputValueA).toBe(0n);
      expect(results.results[0].outputValueB).toBe(0n);
      expect(results.results[0].isAsync).toBe(true);
      const gasToConvert = results.gasUsed;
  
      const beforeFinalise = await getBalances(
        contractSpec.trancheAddress,
        contractSpec.underlyingAddress,
        signer,
        balancerAddress,
        elementBridge.address,
        rollupContract.address
      );
  
      await setBlockchainTime(contractSpec.expiry);
  
      await expect(elementBridge.canFinalise(interactionNonce)).resolves.toBe(
        true
      );
  
      const result = await rollupContract.processAsyncDefiInteraction(
        signer,
        interactionNonce
      );
  
      const gasToFinalise = result.gasUsed;
  
      const afterFinalise = await getBalances(
        contractSpec.trancheAddress,
        contractSpec.underlyingAddress,
        signer,
        balancerAddress,
        elementBridge.address,
        rollupContract.address
      );

      checkBalances(beforeConvert.quantities, afterConvert.quantities, beforeFinalise.quantities, afterFinalise.quantities);
  
      await expect(elementBridge.canFinalise(interactionNonce)).resolves.toBe(
        false
      );

      const gasUsage = `Asset ${
        poolSpec.name
      }, expiry ${new Date(poolSpec.expiry * 1000)}, gas to convert: ${
        gasToConvert
      }, gas to finalise: ${gasToFinalise}`
      console.log(gasUsage);
    });
  });


  it("all assets and all expiries", async () => {
    const numInteractionsPerExpiry = 10n;
    const tokens = vaultConfig.tokens;

    const blockNumBefore = await ethers.provider.getBlockNumber();
    const blockBefore = await ethers.provider.getBlock(blockNumBefore);
    const currentTime = blockBefore.timestamp;
    let goodSpecs: ElementPoolSpec[] = [];
    const failedSpecs: ElementPoolSpec[] = [];
    const assetNames = Object.keys(tokens);
    const depositPerInteraction = new Map<string, bigint>();

    for (let i = 0; i < assetNames.length; i++) {
      const assetName = assetNames[i];
      if (assetSpecs.specs.has(assetName)) {
        const assetSpec = assetSpecs.specs.get(assetName)!;
        if (assetSpec.disabled) {
          continue;
        }
        const requiredToken = {
          amount: numInteractionsPerExpiry * 10n ** assetSpec.quantityExponent,
          erc20Address: tokens[assetName],
          name: assetName,
        };
        try {
          await rollupContract.preFundContractWithToken(signer, requiredToken);
          const poolSpecs = buildPoolSpecs(assetName, vaultConfig);
          if (!poolSpecs.length) {
            continue;
          }
          goodSpecs.push(...poolSpecs);
          const underlyingContract = new Contract(
            requiredToken.erc20Address,
            ERC20.abi,
            signer
          );
          const balance = await underlyingContract.balanceOf(
            rollupContract.address
          );
          const numInteractions =
            numInteractionsPerExpiry * BigInt(poolSpecs.length);
          const amountPerInteraction = balance.toBigInt() / numInteractions;
          depositPerInteraction.set(
            requiredToken.erc20Address,
            amountPerInteraction
          );
        } catch (e) {
          console.log(
            `Failed to fund rollup with ${requiredToken.amount} tokens of ${requiredToken.name}`,
            e
          );
          failedSpecs.push(...buildPoolSpecs(assetName, vaultConfig));
        }
      }
    }

    const register = async (spec: ElementPoolSpec) => {
      await elementBridge
        .registerConvergentPoolAddress(
          signer,
          spec.poolAddress,
          spec.wrappedPositionAddress,
          spec.expiry
        )
        .catch(fixEthersStackTrace);
    };

    const tempSpecs: ElementPoolSpec[] = [];
    for (let i = 0; i < goodSpecs.length; i++) {
      const currentSpec = goodSpecs[i];
      if (currentSpec.expiry <= currentTime) {
        failedSpecs.push(currentSpec);
        continue;
      }
      try {
        await register(currentSpec);
        tempSpecs.push(currentSpec);
      } catch (e) {
        console.log(
          `Failed to register ${currentSpec.name}: ${new Date(
            currentSpec.expiry * 1000
          )}`
        );
        failedSpecs.push(currentSpec);
      }
    }

    goodSpecs = tempSpecs;

    const interactions: Interaction[] = [];

    let interactionNonce = 1n;
    for (let i = 0; i < numInteractionsPerExpiry; i++) {
      for (let j = 0; j < goodSpecs.length; j++) {
        const currentSpec = goodSpecs[j];
        const inputAsset = {
          assetType: AztecAssetType.ERC20,
          id: 1,
          erc20Address: currentSpec.underlyingAddress,
        } as AztecAsset;
        const outputAsset = inputAsset;

        const balancesBefore = await getBalances(
          currentSpec.trancheAddress,
          currentSpec.underlyingAddress,
          signer,
          balancerAddress,
          elementBridge.address,
          rollupContract.address
        );
        const quantity = depositPerInteraction.get(
          currentSpec.underlyingAddress
        )!;


        const results =
          await rollupContract.convert(
            signer,
            elementBridge.address,
            inputAsset,
            {},
            outputAsset,
            {},
            quantity,
            interactionNonce,
            BigInt(currentSpec.expiry)
          );

        const balancesAfter = await getBalances(
          currentSpec.trancheAddress,
          currentSpec.underlyingAddress,
          signer,
          balancerAddress,
          elementBridge.address,
          rollupContract.address
        );

        interactions.push({
          amount: quantity,
          spec: currentSpec,
          nonce: interactionNonce,
          gasUsedConvert: results.gasUsed,
          gasUsedFinalise: 0n,
          finalised: false,
          beforeConvert: balancesBefore.quantities,
          afterConvert: balancesAfter.quantities,
        });

        expect(results.results.length).toBe(1);
        expect(results.results[0].outputValueA).toBe(0n);
        expect(results.results[0].outputValueB).toBe(0n);
        expect(results.results[0].isAsync).toBe(true);
        interactionNonce++;
      }
    }

    expect(goodSpecs.length).toBeTruthy();
    const maxExpiry = goodSpecs.map((x) => x.expiry).sort()[
      goodSpecs.length - 1
    ];

    await setBlockchainTime(maxExpiry);

    for (let i = 0; i < interactions.length; i++) {
      const interaction = interactions[i];
      const currentSpec = interaction.spec;

      await expect(elementBridge.canFinalise(interaction.nonce)).resolves.toBe(
        true
      );

      const balancesBefore = await getBalances(
        currentSpec.trancheAddress,
        currentSpec.underlyingAddress,
        signer,
        balancerAddress,
        elementBridge.address,
        rollupContract.address
      );
      interaction.beforefinalise = balancesBefore.quantities;
      const result = await rollupContract.processAsyncDefiInteraction(
        signer,
        interaction.nonce
      );
      interaction.gasUsedFinalise = result.gasUsed;
      expect(result.outputValueB).toEqual(0n);
      expect(result.outputValueA).toBeGreaterThan(0n);

      const balancesAfter = await getBalances(
        currentSpec.trancheAddress,
        currentSpec.underlyingAddress,
        signer,
        balancerAddress,
        elementBridge.address,
        rollupContract.address
      );
      interaction.afterFinalise = balancesAfter.quantities;

      checkBalances(
        interaction.beforeConvert,
        interaction.afterConvert,
        interaction.beforefinalise!,
        interaction.afterFinalise!
      );

      await expect(elementBridge.canFinalise(interaction.nonce)).resolves.toBe(
        false
      );
    }

    logInteractions(interactions, 'All in - all out');
  });

  it("finalises an eligible interaction after each convert", async () => {
    const numInteractionsPerExpiry = 10n;
    const tokens = vaultConfig.tokens;

    const blockNumBefore = await ethers.provider.getBlockNumber();
    const blockBefore = await ethers.provider.getBlock(blockNumBefore);
    const currentTime = blockBefore.timestamp;
    let goodSpecs: ElementPoolSpec[] = [];
    const failedSpecs: ElementPoolSpec[] = [];
    const assetNames = Object.keys(tokens);
    const depositPerInteraction = new Map<string, bigint>();

    for (let i = 0; i < assetNames.length; i++) {
      const assetName = assetNames[i];
      if (assetSpecs.specs.has(assetName)) {
        const assetSpec = assetSpecs.specs.get(assetName)!;
        if (assetSpec.disabled) {
          continue;
        }
        const requiredToken = {
          amount: numInteractionsPerExpiry * 10n ** assetSpec.quantityExponent,
          erc20Address: tokens[assetName],
          name: assetName,
        };
        try {
          console.log(`Purchasing ${requiredToken.amount} of ${requiredToken.name}`);
          await rollupContract.preFundContractWithToken(signer, requiredToken);
          const poolSpecs = buildPoolSpecs(assetName, vaultConfig);
          if (!poolSpecs.length) {
            continue;
          }
          goodSpecs.push(...poolSpecs);
          const underlyingContract = new Contract(
            requiredToken.erc20Address,
            ERC20.abi,
            signer
          );
          const balance = await underlyingContract.balanceOf(
            rollupContract.address
          );
          const numInteractions =
            numInteractionsPerExpiry * BigInt(poolSpecs.length);
          const amountPerInteraction = balance.toBigInt() / numInteractions;
          depositPerInteraction.set(
            requiredToken.erc20Address,
            amountPerInteraction
          );
        } catch (e) {
          console.log(
            `Failed to fund rollup with ${requiredToken.amount} tokens of ${requiredToken.name}`,
            e
          );
          failedSpecs.push(...buildPoolSpecs(assetName, vaultConfig));
        }
      }
    }

    const register = async (spec: ElementPoolSpec) => {
      await elementBridge
        .registerConvergentPoolAddress(
          signer,
          spec.poolAddress,
          spec.wrappedPositionAddress,
          spec.expiry
        )
        .catch(fixEthersStackTrace);
    };

    const tempSpecs: ElementPoolSpec[] = [];
    for (let i = 0; i < goodSpecs.length; i++) {
      const currentSpec = goodSpecs[i];
      if (currentSpec.expiry <= currentTime) {
        failedSpecs.push(currentSpec);
        continue;
      }
      try {
        await register(currentSpec);
        tempSpecs.push(currentSpec);
      } catch (e) {
        console.log(
          `Failed to register ${currentSpec.name}: ${new Date(
            currentSpec.expiry * 1000
          )}`
        );
        failedSpecs.push(currentSpec);
      }
    }

    //     console.log
    //     Current time: 1642114798

    //       at Object.<anonymous> (bridges/ElementFinance/tests/element_bridge.test.ts:1071:13)

    //   console.log
    //     Epirations  [
    //       1628997564, 1632834462, 1634325622,
    //       1634346845, 1635528110, 1636746083,
    //       1637941844, 1639727861, 1640620258,

    // 	Jan 28
    //       1643382446, 1643382460, 1643382476,
    //       1643382514,

    // 	1644601070, 1644604852, // Feb 11
    // Apr 15
    //       1650025565,

    // Apr 29
    // 	1651240496, 1651247155,
    //       1651253068, 1651264326, 1651265241,
    //       1651267340, 1651275535
    //     ]

    goodSpecs = tempSpecs;
    const interactions: Interaction[] = [];

    const sortedSpecs = goodSpecs.sort((a, b) => {
      if (a.expiry < b.expiry) return -1;
      if (a.expiry > a.expiry) return 1;
      return 0;
    });
    const expirySet1 = sortedSpecs.splice(0, 3);
    const expirySet2 = sortedSpecs.splice(0, 3);
    const expirySet3 = sortedSpecs.splice(0, 3);
    let interactionNonce = 1n;
    let finaliseIndex = 0;
    const convertExpirySet = async (
      expirySet: ElementPoolSpec[],
      willFinalise: boolean
    ) => {
      for (let i = 0; i < expirySet.length; i++) {
        const interactionsForThisExpiry: Interaction[] = [];
        for (let j = 0; j < numInteractionsPerExpiry; j++) {
          const currentSpec = expirySet[i];
          const inputAsset = {
            assetType: AztecAssetType.ERC20,
            id: 1,
            erc20Address: currentSpec.underlyingAddress,
          } as AztecAsset;
          const outputAsset = inputAsset;

          const balancesBefore = await getBalances(
            currentSpec.trancheAddress,
            currentSpec.underlyingAddress,
            signer,
            balancerAddress,
            elementBridge.address,
            rollupContract.address
          );

          if (willFinalise) {
            const balancesBeforeFinalise = await getBalances(
              interactions[finaliseIndex].spec.trancheAddress,
              interactions[finaliseIndex].spec.underlyingAddress,
              signer,
              balancerAddress,
              elementBridge.address,
              rollupContract.address
            );
            interactions[finaliseIndex].beforefinalise = balancesBeforeFinalise.quantities;
            
          }

          const quantity = depositPerInteraction.get(
            currentSpec.underlyingAddress
          )!;

          const results =
            await rollupContract.convert(
              signer,
              elementBridge.address,
              inputAsset,
              {},
              outputAsset,
              {},
              quantity,
              interactionNonce,
              BigInt(currentSpec.expiry)
            );

          const balancesAfter = await getBalances(
            currentSpec.trancheAddress,
            currentSpec.underlyingAddress,
            signer,
            balancerAddress,
            elementBridge.address,
            rollupContract.address
          );

          if (willFinalise) {
            const balancesAfterFinalise = await getBalances(
              interactions[finaliseIndex].spec.trancheAddress,
              interactions[finaliseIndex].spec.underlyingAddress,
              signer,
              balancerAddress,
              elementBridge.address,
              rollupContract.address
            );
            interactions[finaliseIndex].afterFinalise = balancesAfterFinalise.quantities;
            interactions[finaliseIndex].finalised = true;
          }

          interactionsForThisExpiry.unshift({
            amount: quantity,
            spec: currentSpec,
            nonce: interactionNonce,
            gasUsedConvert: results.gasUsed,
            gasUsedFinalise: 0n,
            finalised: false,
            beforeConvert: balancesBefore.quantities,
            afterConvert: balancesAfter.quantities,
            finalisedNonce: willFinalise ? interactions[finaliseIndex].nonce : undefined
          });

          expect(results.results.length).toBe(willFinalise ? 2 : 1);

          let resultIndex = 0;
          if (willFinalise) {
            expect(results.results[resultIndex].outputValueA).toBeGreaterThan(interactions[finaliseIndex].amount);
            expect(results.results[resultIndex].outputValueB).toBe(0n);
            expect(results.results[resultIndex].isAsync).toBe(false);
            resultIndex++;
          }
          expect(results.results[resultIndex].outputValueA).toBe(0n);
          expect(results.results[resultIndex].outputValueB).toBe(0n);
          expect(results.results[resultIndex].isAsync).toBe(true);
          interactionNonce++;
          if (willFinalise) {
            finaliseIndex++;
          }
        }
        interactions.push(...interactionsForThisExpiry);
      }
    };

    await convertExpirySet(expirySet1, false);
    await setBlockchainTime(expirySet1[expirySet1.length - 1].expiry);
    await convertExpirySet(expirySet2, true);
    await setBlockchainTime(expirySet2[expirySet2.length - 1].expiry);
    await convertExpirySet(expirySet3, true);
    await setBlockchainTime(expirySet3[expirySet3.length - 1].expiry);

    for (let i = 0; i < interactions.length; i++) {
      const interaction = interactions[i];
      const currentSpec = interaction.spec;

      if (!interaction.finalised) {
        await expect(elementBridge.canFinalise(interaction.nonce)).resolves.toBe(
          true
        );
  
        const balancesBefore = await getBalances(
          currentSpec.trancheAddress,
          currentSpec.underlyingAddress,
          signer,
          balancerAddress,
          elementBridge.address,
          rollupContract.address
        );
        interaction.beforefinalise = balancesBefore.quantities;
        
        const result = await rollupContract.processAsyncDefiInteraction(
          signer,
          interaction.nonce
        );
        interaction.gasUsedFinalise = result.gasUsed;
        expect(result.outputValueB).toEqual(0n);
        expect(result.outputValueA).toBeGreaterThan(0n);
  
        const balancesAfter = await getBalances(
          currentSpec.trancheAddress,
          currentSpec.underlyingAddress,
          signer,
          balancerAddress,
          elementBridge.address,
          rollupContract.address
        );
        interaction.afterFinalise = balancesAfter.quantities;
      }

      checkBalances(
        interaction.beforeConvert,
        interaction.afterConvert,
        interaction.beforefinalise!,
        interaction.afterFinalise!
      );

      await expect(elementBridge.canFinalise(interaction.nonce)).resolves.toBe(
        false
      );
    }

    logInteractions(interactions, 'One in - one out');
  });

  // This requires the removal of the requirement within the ElementBridge for convert and finalise to be called by the rollup contract
  // This is useful for determining the gas consumption of the element bridge contract
  (Object.keys(vaultConfig.tokens).flatMap(x => {
    const assetSpec = assetSpecs.specs.get(x);
    if (!assetSpec || assetSpec.disabled) {
      return [];
    }
    return buildPoolSpecs(x, vaultConfig);
  })).forEach((poolSpec: ElementPoolSpec) => {
    it.skip(`directly finalising for ${poolSpec.name} - ${new Date(poolSpec.expiry * 1000)} should succeed`, async () => {
      const contractSpec = poolSpec;
      const currentTimestamp = await getCurrentBlockTime();
      if (currentTimestamp >= poolSpec.expiry) {
        return;
      }
  
      const quantityExponent = assetSpecs.specs.get(poolSpec.name)!.quantityExponent;
      const quantityToDeposit = 1n * 10n ** quantityExponent;
      const interactionNonce = 68n;

      try {
        await rollupContract.preFundContractWithToken(signer, {
          erc20Address: contractSpec.underlyingAddress,
          amount: quantityToDeposit,
          name: poolSpec.name
        }, elementBridge.address);
    
        const register = async () => {
          await elementBridge
            .registerConvergentPoolAddress(
              signer,
              contractSpec.poolAddress,
              contractSpec.wrappedPositionAddress,
              contractSpec.expiry
            )
            .catch(fixEthersStackTrace);
        };
    
        await register();
      } catch (e) {
        return;
      }
  
      // for the element bridge, input assets and output assets are the same
      const inputAsset = {
        assetType: AztecAssetType.ERC20,
        id: 1,
        erc20Address: contractSpec.underlyingAddress,
      } as AztecAsset;
      const outputAsset = inputAsset;

  
      const results =
        await elementBridge.convert(
          signer,
          elementBridge.address,
          inputAsset,
          {},
          outputAsset,
          {},
          quantityToDeposit,
          interactionNonce,
          BigInt(contractSpec.expiry)
        );

      const gasToConvert = results.gasUsed;
  
      await setBlockchainTime(contractSpec.expiry);
  
      await expect(elementBridge.canFinalise(interactionNonce)).resolves.toBe(
        true
      );
  
      const result = await elementBridge.finalise(
        signer,
        elementBridge.address,
        inputAsset,
        {},
        outputAsset,
        {},
        interactionNonce,
        BigInt(contractSpec.expiry)
      );
  
      const gasToFinalise = result.gasUsed;

      const gasUsage = `Asset ${
        poolSpec.name
      }, expiry ${new Date(poolSpec.expiry * 1000)}, gas to convert: ${
        gasToConvert
      }, gas to finalise: ${gasToFinalise}`
      console.log(gasUsage);
    });
  });

  // This requires the removal of the requirement within the ElementBridge for convert and finalise to be called by the rollup contract
  // This is useful for determining the gas consumption of the element bridge contract
  it.skip("all assets and all expiries - directly to the bridge", async () => {
    const numInteractionsPerExpiry = 10n;
    const tokens = vaultConfig.tokens;

    const blockNumBefore = await ethers.provider.getBlockNumber();
    const blockBefore = await ethers.provider.getBlock(blockNumBefore);
    const currentTime = blockBefore.timestamp;
    let goodSpecs: ElementPoolSpec[] = [];
    const failedSpecs: ElementPoolSpec[] = [];
    const assetNames = Object.keys(tokens);
    const depositPerInteraction = new Map<string, bigint>();

    for (let i = 0; i < assetNames.length; i++) {
      const assetName = assetNames[i];
      if (assetSpecs.specs.has(assetName)) {
        const assetSpec = assetSpecs.specs.get(assetName)!;
        if (assetSpec.disabled) {
          continue;
        }
        const requiredToken = {
          amount: numInteractionsPerExpiry * 10n ** assetSpec.quantityExponent,
          erc20Address: tokens[assetName],
          name: assetName,
        };
        try {
          await rollupContract.preFundContractWithToken(signer, requiredToken, elementBridge.address);
          const poolSpecs = buildPoolSpecs(assetName, vaultConfig);
          if (!poolSpecs.length) {
            continue;
          }
          goodSpecs.push(...poolSpecs);
          const underlyingContract = new Contract(
            requiredToken.erc20Address,
            ERC20.abi,
            signer
          );
          const balance = await underlyingContract.balanceOf(
            elementBridge.address
          );
          const numInteractions =
            numInteractionsPerExpiry * BigInt(poolSpecs.length);
          const amountPerInteraction = balance.toBigInt() / numInteractions;
          depositPerInteraction.set(
            requiredToken.erc20Address,
            amountPerInteraction
          );
        } catch (e) {
          console.log(
            `Failed to fund rollup with ${requiredToken.amount} tokens of ${requiredToken.name}`,
            e
          );
          failedSpecs.push(...buildPoolSpecs(assetName, vaultConfig));
        }
      }
    }

    const register = async (spec: ElementPoolSpec) => {
      await elementBridge
        .registerConvergentPoolAddress(
          signer,
          spec.poolAddress,
          spec.wrappedPositionAddress,
          spec.expiry
        )
        .catch(fixEthersStackTrace);
    };

    const tempSpecs: ElementPoolSpec[] = [];
    for (let i = 0; i < goodSpecs.length; i++) {
      const currentSpec = goodSpecs[i];
      if (currentSpec.expiry <= currentTime) {
        failedSpecs.push(currentSpec);
        continue;
      }
      try {
        await register(currentSpec);
        tempSpecs.push(currentSpec);
      } catch (e) {
        console.log(
          `Failed to register ${currentSpec.name}: ${new Date(
            currentSpec.expiry * 1000
          )}`
        );
        failedSpecs.push(currentSpec);
      }
    }

    goodSpecs = tempSpecs;

    const interactions: Interaction[] = [];

    let interactionNonce = 1n;
    for (let i = 0; i < numInteractionsPerExpiry; i++) {
      for (let j = 0; j < goodSpecs.length; j++) {
        const currentSpec = goodSpecs[j];
        const inputAsset = {
          assetType: AztecAssetType.ERC20,
          id: 1,
          erc20Address: currentSpec.underlyingAddress,
        } as AztecAsset;
        const outputAsset = inputAsset;

        const quantity = depositPerInteraction.get(
          currentSpec.underlyingAddress
        )!;


        const results =
          await elementBridge.convert(
            signer,
            elementBridge.address,
            inputAsset,
            {},
            outputAsset,
            {},
            quantity,
            interactionNonce,
            BigInt(currentSpec.expiry)
          );

        interactions.push({
          amount: quantity,
          spec: currentSpec,
          nonce: interactionNonce,
          gasUsedConvert: results.gasUsed,
          gasUsedFinalise: 0n,
          finalised: false,
          beforeConvert: {} as SwapQuantities,
          afterConvert: {} as SwapQuantities
        });

        interactionNonce++;
      }
    }

    expect(goodSpecs.length).toBeTruthy();
    const maxExpiry = goodSpecs.map((x) => x.expiry).sort()[
      goodSpecs.length - 1
    ];

    await setBlockchainTime(maxExpiry);

    for (let i = 0; i < interactions.length; i++) {
      const interaction = interactions[i];
      const currentSpec = interaction.spec;

      const inputAsset = {
        assetType: AztecAssetType.ERC20,
        id: 1,
        erc20Address: currentSpec.underlyingAddress,
      } as AztecAsset;
      const outputAsset = inputAsset;

      await expect(elementBridge.canFinalise(interaction.nonce)).resolves.toBe(
        true
      );

      console.log(`About to finalise `, currentSpec.name);

      const result = await elementBridge.finalise(
        signer,
        elementBridge.address,
        inputAsset,
        {},
        outputAsset,
        {},
        interaction.nonce,
        BigInt(currentSpec.expiry)
      );
      interaction.gasUsedFinalise = result.gasUsed;

      await expect(elementBridge.canFinalise(interaction.nonce)).resolves.toBe(
        false
      );
    }

    logInteractions(interactions, 'All in - all out directly to the bridge');
  });
});


