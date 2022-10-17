// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {DataProvider} from "../../aztec/DataProvider.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";

contract DataProviderDeployment is BaseDeployment {
    function deploy() public returns (address) {
        emit log("Deploying Data Provider");

        vm.broadcast();
        DataProvider provider = new DataProvider(ROLLUP_PROCESSOR);
        emit log_named_address("Data provider deployed to", address(provider));

        return address(provider);
    }

    function read() public {
        // TODO: Input data provider on network to read
        readProvider(address(0));
    }

    function readBogota() public {
        readProvider(0x3457D3CC919D01FC41dB41c9Ce3A5C29cbD57d37);
    }

    function readProvider(address _provider) public {
        DataProvider provider = DataProvider(_provider);

        emit log_named_address("Data provider", _provider);

        IRollupProcessor rp = provider.ROLLUP_PROCESSOR();

        if (rp.allowThirdPartyContracts()) {
            emit log("Third parties can deploy bridges");
        } else {
            emit log("Third parties cannot deploy bridges");
        }

        emit log(" - Assets");
        DataProvider.AssetData[] memory assets = provider.getAssets();
        for (uint256 i = 0; i < assets.length; i++) {
            DataProvider.AssetData memory asset = assets[i];
            if (i == 0 || asset.assetId != 0) {
                uint256 gas = i > 0 ? rp.assetGasLimits(asset.assetId) : 30000;
                emit log_named_string(
                    string(abi.encodePacked("AssetId ", Strings.toString(asset.assetId))),
                    string(abi.encodePacked(asset.label, " (", Strings.toString(gas), " gas)"))
                );
            }
        }
        emit log(" - Bridges");
        DataProvider.BridgeData[] memory bridges = provider.getBridges();
        for (uint256 i = 0; i < bridges.length; i++) {
            DataProvider.BridgeData memory bridge = bridges[i];
            if (bridge.bridgeAddressId != 0) {
                uint256 gas = rp.bridgeGasLimits(bridge.bridgeAddressId);
                emit log_string(
                    string(
                        abi.encodePacked(
                            "AddressId ",
                            Strings.toString(bridge.bridgeAddressId),
                            ", address ",
                            Strings.toHexString(bridge.bridgeAddress),
                            ", ",
                            bridge.label,
                            " (",
                            Strings.toString(gas),
                            " gas)"
                        )
                    )
                );
            }
        }
    }

    function deployAndListMany() public returns (address) {
        address provider = deploy();

        uint256[] memory assetIds = new uint256[](8);
        string[] memory assetTags = new string[](8);
        for (uint256 i = 0; i < assetIds.length; i++) {
            assetIds[i] = i;
        }
        assetTags[0] = "eth";
        assetTags[1] = "dai";
        assetTags[2] = "wsteth";
        assetTags[3] = "vydai";
        assetTags[4] = "vyweth";
        assetTags[5] = "weweth";
        assetTags[6] = "wewsteth";
        assetTags[7] = "wedai";

        uint256[] memory bridgeAddressIds = new uint256[](7);
        string[] memory bridgeTags = new string[](7);

        bridgeAddressIds[0] = 1;
        bridgeAddressIds[1] = 6;
        bridgeAddressIds[2] = 7;
        bridgeAddressIds[3] = 8;
        bridgeAddressIds[4] = 9;
        bridgeAddressIds[5] = 10;
        bridgeAddressIds[6] = 11;

        bridgeTags[0] = "ElementBridge";
        bridgeTags[1] = "CurveStEthBridge";
        bridgeTags[2] = "YearnBridge_Deposit";
        bridgeTags[3] = "YearnBridge_Withdraw";
        bridgeTags[4] = "ElementBridge2M";
        bridgeTags[5] = "ERC4626";
        bridgeTags[6] = "DCA400K";

        vm.broadcast();
        DataProvider(provider).addAssetsAndBridges(assetIds, assetTags, bridgeAddressIds, bridgeTags);

        return provider;
    }

    function _listBridge(
        address _provider,
        uint256 _bridgeAddressId,
        string memory _tag
    ) internal {
        vm.broadcast();
        DataProvider(_provider).addBridge(_bridgeAddressId, _tag);
        emit log_named_uint(string(abi.encodePacked("[Bridge] Listed ", _tag, " at")), _bridgeAddressId);
    }

    function _listAsset(
        address _provider,
        uint256 _assetId,
        string memory _tag
    ) internal {
        vm.broadcast();
        DataProvider(_provider).addAsset(_assetId, _tag);
        emit log_named_uint(string(abi.encodePacked("[Asset]  Listed ", _tag, " at")), _assetId);
    }
}
