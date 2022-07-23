import { HardhatUserConfig, subtask } from "hardhat/config";
import "@typechain/hardhat";

const { TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS } = require("hardhat/builtin-tasks/task-names");

subtask(TASK_COMPILE_SOLIDITY_GET_SOURCE_PATHS).setAction(async (_, __, runSuper) => {
  const paths = await runSuper();

  // Do not generate types for files in the src/test folder unless they are in interface subfolder.
  // (Types of all the interfaces are needed in end to end tests.)
  return paths.filter((p: any) => !p.includes("src/test/") || p.includes("interface"));
});

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.10",
    settings: {
      optimizer: { enabled: true, runs: 200 },
    },
  },
  typechain: {
    target: "ethers-v5",
  },
  networks: {
    ganache: {
      url: `http://${process.env.GANACHE_HOST || "localhost"}:8545`,
    },
    hardhat: {
      blockGasLimit: 15000000,
    },
  },
  paths: {
    sources: "src/",
    artifacts: "./artifacts",
  },
};

export default config;
