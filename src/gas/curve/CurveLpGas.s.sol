// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CurveStEthBridge} from "../../bridges/curve/CurveStEthBridge.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {ISubsidy} from "../../aztec/interfaces/ISubsidy.sol";

import {CurveStethLpDeployment} from "../../deployment/curve/CurveStethLpDeployment.s.sol";
import {GasBase} from "../base/GasBase.sol";

interface IRead {
    function defiBridgeProxy() external view returns (address);
}

contract CurveLpMeasure is CurveStethLpDeployment {
    GasBase internal gasBase;
    CurveStEthBridge internal bridge;

    function measure() public {
        address defiProxy = IRead(ROLLUP_PROCESSOR).defiBridgeProxy();
        vm.label(defiProxy, "DefiProxy");

        vm.broadcast();
        gasBase = new GasBase(defiProxy);

        address temp = ROLLUP_PROCESSOR;
        ROLLUP_PROCESSOR = address(gasBase);
        (address bridge, address lpToken) = deployAndList();
        ROLLUP_PROCESSOR = temp;

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory eth = AztecTypes.AztecAsset({
            id: 0,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.ETH
        });
        AztecTypes.AztecAsset memory lpAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: lpToken,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        vm.broadcast();
        address(gasBase).call{value: 2 ether}("");
        emit log_named_uint("Balance of ", address(gasBase).balance);

        // add liquidity eth
        {
            vm.broadcast();
            gasBase.convert(bridge, eth, empty, lpAsset, empty, 1 ether, 0, 0, address(this), 250000);
            emit log_named_uint("bal", IERC20(lpAsset.erc20Address).balanceOf(address(gasBase)));
        }

        // add liquidity eth
        {
            vm.broadcast();
            gasBase.convert(bridge, eth, empty, lpAsset, empty, 1 ether, 0, 0, address(this), 250000);
            emit log_named_uint("bal", IERC20(lpAsset.erc20Address).balanceOf(address(gasBase)));
        }

        /*
        // add liquidity wsteth
        {
            emit log_named_uint("bal", IERC20(lpAsset.erc20Address).balanceOf(address(gasBase)));

            vm.broadcast();
            gasBase.convert(bridge, lpAsset, empty, eth, empty, 0.1 ether, 1, 1, address(this), 250000);
            emit log_named_uint("bal", IERC20(lpAsset.erc20Address).balanceOf(address(gasBase)));
        }*/
    }
}
