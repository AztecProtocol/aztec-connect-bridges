// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {DataProvider} from "../../aztec/DataProvider.sol";

contract DataProviderDeployment is BaseDeployment {
    function deploy() public returns (address) {
        emit log("Deploying Data Provider");

        vm.broadcast();
        DataProvider provider = new DataProvider(ROLLUP_PROCESSOR);
        emit log_named_address("Data provider deployed to", address(provider));

        return address(provider);
    }

    function listBridge(
        address _provider,
        uint256 _bridgeAddressId,
        string memory _tag
    ) public {
        vm.broadcast();
        DataProvider(_provider).addBridge(_bridgeAddressId, _tag);

        emit log_named_uint(string(abi.encodePacked("[Bridge] Listed ", _tag, " at")), _bridgeAddressId);
    }

    function listAsset(
        address _provider,
        uint256 _assetId,
        string memory _tag
    ) public {
        vm.broadcast();
        DataProvider(_provider).addAsset(_assetId, _tag);
        emit log_named_uint(string(abi.encodePacked("[Asset]  Listed ", _tag, " at")), _assetId);
    }

    function deployAndListMany() public {}

    function deployAndListDevNet() public {
        address provider = deploy();

        listAsset(provider, 1, "Dai");
        listAsset(provider, 2, "WSTETH");
        listAsset(provider, 3, "vyDai");
        listAsset(provider, 4, "vyWeth");

        listBridge(provider, 1, "Element Fixed Yield");
        listBridge(provider, 6, "Curve swap steth pool");
        listBridge(provider, 7, "Yearn Deposit");
        listBridge(provider, 8, "Yearn Withdraw");
        listBridge(provider, 9, "DCA DAI/ETH 7 Days");

        DataProvider.BridgeData memory bridge = DataProvider(provider).getBridge("Yearn Withdraw");
        emit log_named_uint(bridge.label, bridge.bridgeAddressId);
    }
}
