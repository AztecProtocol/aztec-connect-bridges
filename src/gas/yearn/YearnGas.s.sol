// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {YearnBridge} from "../../bridges/yearn/YearnBridge.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {ISubsidy} from "../../aztec/interfaces/ISubsidy.sol";

import {YearnDeployment} from "../../deployment/yearn/YearnDeployment.s.sol";
import {GasBase} from "../base/GasBase.sol";

interface IRead {
    function defiBridgeProxy() external view returns (address);
}

contract YearnMeasure is YearnDeployment {
    GasBase internal gasBase;
    YearnBridge internal bridge;

    function measure() public {
        address defiProxy = IRead(ROLLUP_PROCESSOR).defiBridgeProxy();
        vm.label(defiProxy, "DefiProxy");

        gasBase = new GasBase(defiProxy);

        address temp = ROLLUP_PROCESSOR;
        ROLLUP_PROCESSOR = address(gasBase);
        address bridge = deployAndList();
        ROLLUP_PROCESSOR = temp;

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory eth = AztecTypes.AztecAsset({
            id: 0,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.ETH
        });
        AztecTypes.AztecAsset memory vyAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: YEARN_REGISTRY.latestVault(WETH),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        vm.deal(address(gasBase), 2 ether);
        emit log_named_uint("Balance of ", address(gasBase).balance);

        // Deposit
        {
            vm.warp(block.timestamp + 1000);

            vm.broadcast();
            uint256 gas = gasBase.convert(bridge, eth, empty, vyAsset, empty, 1 ether, 0, 0, address(this), 200000);

            emit log_named_uint("Gas      ", gas);
        }

        // Withdraw
        {
            vm.warp(block.timestamp + 1000);

            emit log_named_uint("bal", IERC20(vyAsset.erc20Address).balanceOf(address(gasBase)));

            vm.broadcast();
            uint256 gas = gasBase.convert(bridge, vyAsset, empty, eth, empty, 0.1 ether, 1, 1, address(this), 200000);
            emit log_named_uint("bal", IERC20(vyAsset.erc20Address).balanceOf(address(gasBase)));

            emit log_named_uint("Gas      ", gas);
        }
    }

    function measureDai() public {
        address defiProxy = IRead(ROLLUP_PROCESSOR).defiBridgeProxy();
        vm.label(defiProxy, "DefiProxy");

        gasBase = new GasBase(defiProxy);

        address temp = ROLLUP_PROCESSOR;
        ROLLUP_PROCESSOR = address(gasBase);
        address bridge = deployAndList();
        ROLLUP_PROCESSOR = temp;

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory dai = AztecTypes.AztecAsset({
            id: 0,
            erc20Address: address(DAI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory vyAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: YEARN_REGISTRY.latestVault(DAI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        deal(DAI, address(gasBase), 2 ether);
        emit log_named_uint("Balance of ", IERC20(DAI).balanceOf(address(gasBase)));

        // Deposit
        {
            vm.warp(block.timestamp + 1000);

            vm.broadcast();
            uint256 gas = gasBase.convert(bridge, dai, empty, vyAsset, empty, 1 ether, 0, 0, address(this), 200000);

            emit log_named_uint("Gas      ", gas);
        }

        // Withdraw
        {
            vm.warp(block.timestamp + 1000);

            emit log_named_uint("bal", IERC20(vyAsset.erc20Address).balanceOf(address(gasBase)));

            vm.broadcast();
            uint256 gas = gasBase.convert(bridge, vyAsset, empty, dai, empty, 0.1 ether, 1, 1, address(this), 200000);
            emit log_named_uint("bal", IERC20(vyAsset.erc20Address).balanceOf(address(gasBase)));

            emit log_named_uint("Gas      ", gas);
        }
    }
}
