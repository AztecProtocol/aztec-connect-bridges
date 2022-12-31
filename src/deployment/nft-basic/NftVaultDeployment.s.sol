// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {NftVault} from "../../bridges/nft-basic/NftVault.sol";
import {AddressRegistry} from "../../bridges/registry/AddressRegistry.sol";

contract NftVaultDeployment is BaseDeployment {
    function deploy(address _addressRegistry) public returns (address) {
        emit log("Deploying NftVault bridge");

        vm.broadcast();
        NftVault bridge = new NftVault(ROLLUP_PROCESSOR, _addressRegistry);

        emit log_named_address("NftVault bridge deployed to", address(bridge));

        return address(bridge);
    }

    function deployAndList(address _addressRegistry) public returns (address) {
        address bridge = deploy(_addressRegistry);

        uint256 addressId = listBridge(bridge, 400000);
        emit log_named_uint("NftVault bridge address id", addressId);

        return bridge;
    }

    function deployAndListAddressRegistry() public returns (address) {
        emit log("Deploying AddressRegistry bridge");

        AddressRegistry bridge = new AddressRegistry(ROLLUP_PROCESSOR);

        emit log_named_address("AddressRegistry bridge deployed to", address(bridge));

        uint256 addressId = listBridge(address(bridge), 400000);
        emit log_named_uint("AddressRegistry bridge address id", addressId);

        return address(bridge);
    }
}
