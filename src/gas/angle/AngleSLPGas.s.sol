// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AngleSLPBridge} from "../../bridges/angle/AngleSLPBridge.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {ISubsidy} from "../../aztec/interfaces/ISubsidy.sol";

import {AngleSLPDeployment} from "../../deployment/angle/AngleSLPDeployment.s.sol";
import {GasBase} from "../base/GasBase.sol";

interface IRead {
    function defiBridgeProxy() external view returns (address);
}

contract AngleMeasure is AngleSLPDeployment {
    GasBase internal gasBase;

    function measureETH() public {
        address defiProxy = IRead(ROLLUP_PROCESSOR).defiBridgeProxy();
        vm.label(defiProxy, "DefiProxy");

        vm.broadcast();
        gasBase = new GasBase(defiProxy);

        address temp = ROLLUP_PROCESSOR;
        ROLLUP_PROCESSOR = address(gasBase);
        AngleSLPBridge bridge = AngleSLPBridge(payable(deployAndList()));
        ROLLUP_PROCESSOR = temp;

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory eth = AztecTypes.AztecAsset({
            id: 0,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.ETH
        });
        AztecTypes.AztecAsset memory sanWethAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: bridge.SANWETH(),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        vm.broadcast();
        address(gasBase).call{value: 2 ether}("");
        emit log_named_uint("ETH balance of gasBase", address(gasBase).balance);

        // Deposit
        {
            vm.broadcast();
            gasBase.convert(address(bridge), eth, empty, sanWethAsset, empty, 1 ether, 0, 0, address(this), 170000);
        }

        uint256 sanWethBalance = IERC20(sanWethAsset.erc20Address).balanceOf(address(gasBase));

        // Withdraw half the sanWeth
        {
            emit log_named_uint("sanWeth balance of gasBase", sanWethBalance);

            vm.broadcast();
            gasBase.convert(
                address(bridge),
                sanWethAsset,
                empty,
                eth,
                empty,
                sanWethBalance / 2,
                1,
                1,
                address(this),
                200000
            );
            emit log_named_uint(
                "sanWeth balance of gasBase",
                IERC20(sanWethAsset.erc20Address).balanceOf(address(gasBase))
            );
        }
    }
}
