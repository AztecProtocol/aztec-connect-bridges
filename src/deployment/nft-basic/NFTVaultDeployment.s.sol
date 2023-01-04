// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {NFTVault} from "../../bridges/nft-basic/NFTVault.sol";
import {AddressRegistry} from "../../bridges/registry/AddressRegistry.sol";

contract NFTVaultDeployment is BaseDeployment {
    function deploy(address _addressRegistry) public returns (address) {
        emit log("Deploying NFTVault bridge");

        vm.broadcast();
        NFTVault bridge = new NFTVault(ROLLUP_PROCESSOR, _addressRegistry);

        emit log_named_address("NFTVault bridge deployed to", address(bridge));

        return address(bridge);
    }

    function deployAndList(address _addressRegistry) public returns (address) {
        address bridge = deploy(_addressRegistry);

        uint256 addressId = listBridge(bridge, 135500);
        emit log_named_uint("NFTVault bridge address id", addressId);

        return bridge;
    }

    function deployAndListAddressRegistry() public returns (address) {
        emit log("Deploying AddressRegistry bridge");

        AddressRegistry bridge = new AddressRegistry(ROLLUP_PROCESSOR);

        emit log_named_address("AddressRegistry bridge deployed to", address(bridge));

        uint256 addressId = listBridge(address(bridge), 120500);
        emit log_named_uint("AddressRegistry bridge address id", addressId);

        return address(bridge);
    }
}
