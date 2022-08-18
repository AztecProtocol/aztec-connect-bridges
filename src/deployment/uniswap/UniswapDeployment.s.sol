// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {UniswapBridge} from "../../bridges/uniswap/UniswapBridge.sol";

contract UniswapDeployment is BaseDeployment {
    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    function setUp() public virtual {
        NETWORK = Network.DEVNET;
        MODE = Mode.BROADCAST;
        configure();
    }

    function deploy() public returns (address) {
        emit log("Deploying uniswap bridge");

        vm.broadcast();
        UniswapBridge bridge = new UniswapBridge(ROLLUP_PROCESSOR);

        emit log_named_address("Example uniswap deployed to", address(bridge));

        address[] memory tokens = new address[](2);
        tokens[0] = DAI;
        tokens[1] = WETH;

        vm.broadcast();
        bridge.preApproveTokens(tokens, tokens);

        return address(bridge);
    }

    function deployAndList() public {
        address bridge = deploy();
        uint256 addressId = listBridge(bridge, 500000);
        emit log_named_uint("Uniswap bridge address id", addressId);
    }
}
