// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BaseDeployment} from "./base/BaseDeployment.s.sol";
import {IRollupProcessor} from "../aztec/interfaces/IRollupProcessor.sol";

import {CompoundDeployment} from "./compound/CompoundDeployment.s.sol";
import {CurveDeployment} from "./curve/CurveDeployment.s.sol";
import {DonationDeployment} from "./donation/DonationDeployment.s.sol";
import {ERC4626Deployment} from "./erc4626/ERC4626Deployment.s.sol";
import {LiquityTroveDeployment} from "./liquity/LiquityTroveDeployment.s.sol";
import {UniswapDeployment} from "./uniswap/UniswapDeployment.s.sol";
import {YearnDeployment} from "./yearn/YearnDeployment.s.sol";

/**
 * A helper script that allow easy deployment of multiple bridges
 */
contract AggregateDeployment is BaseDeployment {
    function deployAndListAll() public {
        emit log("--- Curve ---");
        {
            CurveDeployment cDeploy = new CurveDeployment();
            cDeploy.setUp();
            cDeploy.deployAndList();
        }

        emit log("--- Yearn ---");
        {
            YearnDeployment yDeploy = new YearnDeployment();
            yDeploy.setUp();
            yDeploy.deployAndList();
        }
    }

    function readStats() public {
        IRollupProcessor rp = IRollupProcessor(ROLLUP_PROCESSOR);

        uint256 assetCount = assetLength();
        emit log_named_uint("Assets added ", assetCount);
        for (uint256 i = 0; i < assetCount; i++) {
            string memory symbol = i > 0 ? IERC20Metadata(rp.getSupportedAsset(i)).symbol() : "Eth";
            uint256 gas = i > 0 ? rp.assetGasLimits(i) : 30000;
            emit log_named_string(
                string(abi.encodePacked("  Asset ", Strings.toString(i))),
                string(abi.encodePacked(symbol, ", ", Strings.toString(gas)))
            );
        }

        uint256 bridgeCount = bridgesLength();
        emit log_named_uint("Bridges added", bridgeCount);
        for (uint256 i = 1; i <= bridgeCount; i++) {
            address bridge = rp.getSupportedBridge(i);
            uint256 gas = rp.bridgeGasLimits(i);
            emit log_named_string(
                string(abi.encodePacked("  Bridge ", Strings.toString(i))),
                string(abi.encodePacked(Strings.toHexString(bridge), ", ", Strings.toString(gas)))
            );
        }
    }
}
