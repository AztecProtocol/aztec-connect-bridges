// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";

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
contract AggregateDeployment is Test {
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
}
