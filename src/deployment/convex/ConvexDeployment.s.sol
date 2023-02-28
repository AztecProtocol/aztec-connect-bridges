// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BaseDeployment} from "../base/BaseDeployment.s.sol";
import {ConvexStakingBridge} from "../../bridges/convex/ConvexStakingBridge.sol";
import {IConvexBooster} from "../../interfaces/convex/IConvexBooster.sol";
import {IConvexStakingBridge} from "../../interfaces/convex/IConvexStakingBridge.sol";

contract ConvexStakingBridgeDeployment is BaseDeployment {
    uint256[] private poolIds = [23, 25]; // supported pool ids [23, 25, 32, 33, 38, 40, 49, 61, 64, 122];

    /**
     * @notice Deploys and lists the bridge
     */
    function deploy() public {
        emit log("Deploying Convex staking bridge");

        vm.broadcast();
        ConvexStakingBridge bridge = new ConvexStakingBridge(ROLLUP_PROCESSOR);
        emit log_named_address("Convex staking bridge deployed to", address(bridge));

        uint256 depositBridgeId = listBridge(address(bridge), 3500000); // deposits
        uint256 withdrawalBridgeId = listBridge(address(bridge), 2500000); // withdrawals

        emit log_named_uint("Convex staking bridge address id for deposits", depositBridgeId);
        emit log_named_uint("Convex staking bridge address id for withdrawals", withdrawalBridgeId);
    }

    /**
     * @notice Load pool(s) and list pool specific Curve LP and corresponding RCT token
     * @dev Use to properly load a pool and set up its assets to the Rollup
     */
    function loadPoolsAndListAssets() public {
        address bridgeAddr = 0x81F3A97eAF582AdE8E32a4F1ED85A63AA84e7296; // #todo actual address of deployed Convex Staking bridge
        // Note: Insert pool ids in the poolIds variable at the top of the contract to have the pools loaded and their respective RCT tokens listed
        for (uint256 i = 0; i < poolIds.length; i++) {
            IConvexStakingBridge(bridgeAddr).loadPool(poolIds[i]);
            _listAssets(bridgeAddr, poolIds[i]);
        }
    }

    /**
     * @notice List pool specific Curve LP and corresponding RCT token for already loaded pool
     * @dev Finish listing of pool specific assets if loadPoolsAndListAssets() was not used to load a pool
     */
    function listTokensByPoolId() public {
        // Warning: Pools have to be already loaded for the listing to be successful
        address bridgeAddr = 0x0000000000000000000000000000000000000000; // #todo actual address of deployed Convex Staking bridge
        // Note: Insert pool ids in the poolIds variable at the top of the contract to have the RCT tokens listed
        for (uint256 i = 0; i < poolIds.length; i++) {
            _listAssets(bridgeAddr, poolIds[i]);
        }
    }

    /**
     * @notice List Curve LP token and RCT token for a given pool
     */
    function _listAssets(address _bridgeAddr, uint256 _poolId) internal {
        (address curveLpToken,,,,,) = IConvexBooster(0xF403C135812408BFbE8713b5A23a04b3D48AAE31).poolInfo(_poolId);
        address rctToken = IConvexStakingBridge(_bridgeAddr).deployedClones(curveLpToken);
        listAsset(curveLpToken, 100000);
        listAsset(rctToken, 100000);
    }
}
