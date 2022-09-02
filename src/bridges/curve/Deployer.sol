// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

contract Deployer {
    function deploy(bytes memory _bytecode) public returns (address deployedAddress) {
        assembly {
            deployedAddress := create(0, add(_bytecode, 0x20), mload(_bytecode))
        }
        require(deployedAddress != address(0), "VyperDeployer could not deploy contract");
    }
}
