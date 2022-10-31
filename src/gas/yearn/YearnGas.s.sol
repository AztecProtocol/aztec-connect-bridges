// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {YearnBridge} from "../../bridges/yearn/YearnBridge.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ISubsidy} from "../../aztec/interfaces/ISubsidy.sol";

import {YearnDeployment} from "../../deployment/yearn/YearnDeployment.s.sol";
import {GasBase} from "../base/GasBase.sol";

interface IRead {
    function defiBridgeProxy() external view returns (address);
}

contract YearnMeasure is YearnDeployment {
    GasBase internal gasBase;
    ISubsidy internal subsidy;

    address internal constant BENEFICIARY = address(0xdeadbeef);

    function measure() public {
        address defiProxy = IRead(ROLLUP_PROCESSOR).defiBridgeProxy();
        vm.label(defiProxy, "DefiProxy");

        vm.broadcast();
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

        vm.broadcast();
        address(gasBase).call{value: 2 ether}("");
        emit log_named_uint("Balance of ", address(gasBase).balance);

        // Deposit
        {
            vm.broadcast();
            gasBase.convert(bridge, eth, empty, vyAsset, empty, 1 ether, 0, 0, address(this), 200000);
        }

        // Withdraw
        {
            emit log_named_uint("bal", IERC20(vyAsset.erc20Address).balanceOf(address(gasBase)));

            vm.broadcast();
            gasBase.convert(bridge, vyAsset, empty, eth, empty, 0.1 ether, 1, 1, address(this), 200000);
            emit log_named_uint("bal", IERC20(vyAsset.erc20Address).balanceOf(address(gasBase)));
        }
    }

    function measureWithSubsidy() public {
        address defiProxy = IRead(ROLLUP_PROCESSOR).defiBridgeProxy();
        vm.label(defiProxy, "DefiProxy");

        vm.broadcast();
        gasBase = new GasBase(defiProxy);

        address temp = ROLLUP_PROCESSOR;
        ROLLUP_PROCESSOR = address(gasBase);
        address bridge = deployAndList();
        ROLLUP_PROCESSOR = temp;

        subsidy = ISubsidy(YearnBridge(payable(bridge)).SUBSIDY());

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

        vm.broadcast();
        subsidy.registerBeneficiary(BENEFICIARY);

        vm.broadcast();
        subsidy.subsidize{value: 1 ether}(bridge, 0, 200);

        vm.broadcast();
        address(gasBase).call{value: 2 ether}("");
        emit log_named_uint("Balance of ", address(gasBase).balance);

        // Deposit
        {
            vm.broadcast();
            gasBase.convert(bridge, eth, empty, vyAsset, empty, 1 ether, 0, 0, BENEFICIARY, 200000);
        }

        // Withdraw
        {
            emit log_named_uint("bal", IERC20(vyAsset.erc20Address).balanceOf(address(gasBase)));

            vm.broadcast();
            gasBase.convert(bridge, vyAsset, empty, eth, empty, 0.1 ether, 1, 1, BENEFICIARY, 200000);
            emit log_named_uint("bal", IERC20(vyAsset.erc20Address).balanceOf(address(gasBase)));
        }

        emit log_named_uint("Subsidy accumulated", subsidy.claimableAmount(BENEFICIARY));
        emit log_named_uint("Subsidy balance    ", address(subsidy).balance);

        {
            if (subsidy.isRegistered(BENEFICIARY)) {
                emit log("Is registered");
            }
            ISubsidy.Subsidy memory sub = subsidy.getSubsidy(bridge, 0);
            emit log_named_uint("available", sub.available);
            emit log_named_uint("gasUsage", sub.gasUsage);
            emit log_named_uint("gasPerMinute", sub.gasPerMinute);
            emit log_named_uint("lastUpdated", sub.lastUpdated);
        }
    }

    function measureWeth() public {
        address defiProxy = IRead(ROLLUP_PROCESSOR).defiBridgeProxy();
        vm.label(defiProxy, "DefiProxy");

        vm.broadcast();
        gasBase = new GasBase(defiProxy);

        address temp = ROLLUP_PROCESSOR;
        ROLLUP_PROCESSOR = address(gasBase);
        address bridge = deployAndList();
        ROLLUP_PROCESSOR = temp;

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory wethAsset = AztecTypes.AztecAsset({
            id: 0,
            erc20Address: address(WETH),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory vyAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: YEARN_REGISTRY.latestVault(WETH),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        vm.broadcast();
        WETH.call{value: 2 ether}("");

        vm.broadcast();
        IERC20(WETH).transfer(address(gasBase), 2 ether);

        emit log_named_uint("Balance of ", IERC20(WETH).balanceOf(address(gasBase)));

        // Deposit
        {
            vm.broadcast();
            gasBase.convert(bridge, wethAsset, empty, vyAsset, empty, 1 ether, 0, 0, address(this), 17500);
        }

        // Withdraw
        {
            emit log_named_uint("bal", IERC20(vyAsset.erc20Address).balanceOf(address(gasBase)));

            vm.broadcast();
            gasBase.convert(bridge, vyAsset, empty, wethAsset, empty, 0.1 ether, 1, 1, address(this), 17500);
            emit log_named_uint("bal", IERC20(vyAsset.erc20Address).balanceOf(address(gasBase)));
        }
    }
}
