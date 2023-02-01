// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {YearnBridge} from "../../bridges/yearn/YearnBridge.sol";
import {IYearnRegistry} from "../../interfaces/yearn/IYearnRegistry.sol";

contract YearnDeployment is BaseDeployment {
    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    IYearnRegistry public constant YEARN_REGISTRY = IYearnRegistry(0x50c1a2eA0a861A967D9d0FFE2AE4012c2E053804);

    function deploy() public returns (address) {
        emit log("Deploying yearn bridge");

        vm.broadcast();
        YearnBridge bridge = new YearnBridge(ROLLUP_PROCESSOR);

        emit log_named_address("Yearn bridge deployed to", address(bridge));

        return address(bridge);
    }

    function approveAsset(address _bridge, address _asset) public returns (address) {
        YearnBridge bridge = YearnBridge(payable(_bridge));
        address latestVault = YEARN_REGISTRY.latestVault(_asset);

        vm.broadcast();
        bridge.preApprove(latestVault);

        return latestVault;
    }

    function approveAssets(address _bridge) public {
        YearnBridge bridge = YearnBridge(payable(_bridge));

        address latestDaiVault = YEARN_REGISTRY.latestVault(DAI);
        address latestWethVault = YEARN_REGISTRY.latestVault(WETH);

        vm.broadcast();
        YearnBridge(payable(bridge)).preApprove(latestDaiVault);

        vm.broadcast();
        YearnBridge(payable(bridge)).preApprove(latestWethVault);
    }

    function deployAndList() public returns (address) {
        address bridge = deploy();

        approveAssets(bridge);

        uint256 depositAddressId = listBridge(bridge, 200000);
        emit log_named_uint("Yearn deposit bridge address id", depositAddressId);

        uint256 withdrawAddressId = listBridge(bridge, 800000);
        emit log_named_uint("Yearn withdraw bridge address id", withdrawAddressId);

        listAsset(YEARN_REGISTRY.latestVault(DAI), 55000);
        listAsset(YEARN_REGISTRY.latestVault(WETH), 55000);

        return bridge;
    }
}
