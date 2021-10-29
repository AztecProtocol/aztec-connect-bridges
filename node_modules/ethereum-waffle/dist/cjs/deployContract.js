"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const ethers_1 = require("ethers");
const ContractJSON_1 = require("./ContractJSON");
const defaultDeployOptions = {
    gasLimit: 4000000,
    gasPrice: 9000000000
};
async function deployContract(signer, contractJSON, args = [], overrideOptions = {}) {
    const bytecode = ContractJSON_1.isStandard(contractJSON) ? contractJSON.evm.bytecode : contractJSON.bytecode;
    if (!ContractJSON_1.hasByteCode(bytecode)) {
        throw new Error('Cannot deploy contract with empty bytecode');
    }
    const factory = new ethers_1.ContractFactory(contractJSON.abi, bytecode, signer);
    const contract = await factory.deploy(...args, {
        ...defaultDeployOptions,
        ...overrideOptions
    });
    await contract.deployed();
    return contract;
}
exports.deployContract = deployContract;
