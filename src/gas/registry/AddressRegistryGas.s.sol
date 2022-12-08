// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {AddressRegistry} from "../../bridges/registry/AddressRegistry.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";

import {AddressRegistryDeployment} from "../../deployment/registry/AddressRegistryDeployment.s.sol";
import {GasBase} from "../base/GasBase.sol";

interface IRead {
    function defiBridgeProxy() external view returns (address);
}

contract AddressRegistryGas is AddressRegistryDeployment {
    GasBase internal gasBase;
    AddressRegistry internal bridge;

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
        AztecTypes.AztecAsset memory eth =
            AztecTypes.AztecAsset({id: 0, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.ETH});
        AztecTypes.AztecAsset memory virtualAsset =
            AztecTypes.AztecAsset({id: 100, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL});

        vm.broadcast();
        address(gasBase).call{value: 2 ether}("");
        emit log_named_uint("Balance of ", address(gasBase).balance);

        // Get virtual assets
        {
            vm.broadcast();
            gasBase.convert(bridge, eth, empty, virtualAsset, empty, 1, 0, 0, address(0), 400000);
        }

        uint256 inputAmount = uint256(uint160(0x2e782B05290A7fFfA137a81a2bad2446AD0DdFEA));
        // register address
        {
            vm.broadcast();
            gasBase.convert(bridge, virtualAsset, empty, virtualAsset, empty, inputAmount, 0, 0, address(0), 400000);
        }
    }
}
