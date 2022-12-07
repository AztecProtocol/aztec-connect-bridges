// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {ElementBridge} from "../../bridges/element/ElementBridge.sol";

contract ElementDeployment is BaseDeployment {
    address internal constant TRANCHE_FACTORY = 0x62F161BF3692E4015BefB05A03a94A40f520d1c0;
    address internal constant ELEMENT_REGISTRY_ADDRESS = 0xc68e2BAb13a7A2344bb81badBeA626012C62C510;
    bytes32 internal constant TRANCHE_BYTECODE_HASH = 0xf481a073666136ab1f5e93b296e84df58092065256d0db23b2d22b62c68e978d;
    address internal constant BALANCER_VAULT = 0xBA12222222228d8Ba445958a75a0704d566BF2C8;

    function deployAndList() public returns (address) {
        emit log("Deploying element bridge");
        vm.broadcast();
        ElementBridge bridge = new ElementBridge(
            ROLLUP_PROCESSOR,
            TRANCHE_FACTORY,
            TRANCHE_BYTECODE_HASH,
            BALANCER_VAULT,
            ELEMENT_REGISTRY_ADDRESS
        );
        emit log_named_address("element bridge deployed to", address(bridge));

        uint256 addressId = listBridge(address(bridge), 800000);
        emit log_named_uint("Curve bridge address id", addressId);

        return address(bridge);
    }

    function registerPool(address _bridge, address _pool, address _position, uint64 _expiry) public {
        if (_expiry < block.timestamp) {
            return;
        }

        string memory symbol = IERC20Metadata(_position).symbol();
        string memory s = string(abi.encodePacked("Registering ", symbol, " pool with expiry at "));

        emit log_named_uint(s, _expiry);

        vm.broadcast();
        ElementBridge(_bridge).registerConvergentPoolAddress(_pool, _position, _expiry);
    }
}
