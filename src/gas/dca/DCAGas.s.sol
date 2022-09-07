// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {UniswapDCABridge} from "../../bridges/dca/UniswapDCABridge.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {ISubsidy} from "../../aztec/interfaces/ISubsidy.sol";

import {DCADeployment} from "../../deployment/dca/DCADeployment.s.sol";
import {GasBase} from "../base/GasBase.sol";

interface IRead {
    function defiBridgeProxy() external view returns (address);
}

contract DCAMeasure is DCADeployment {
    GasBase internal gasBase;
    UniswapDCABridge internal bridge;

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
        AztecTypes.AztecAsset memory daiAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: 0x6B175474E89094C44Da98b954EedeAC495271d0F,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        vm.broadcast();
        address(gasBase).call{value: 2 ether}("");
        emit log_named_uint("Balance of ", address(gasBase).balance);

        // Create DCA for 7 days
        {
            vm.broadcast();
            gasBase.convert(bridge, eth, empty, daiAsset, empty, 1 ether, 0, 7, address(this), 400000);
        }
    }
}
