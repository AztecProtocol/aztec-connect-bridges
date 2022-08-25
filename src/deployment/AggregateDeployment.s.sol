// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Script} from "forge-std/Script.sol";

import {CompoundDeployment} from "./compound/CompoundDeployment.s.sol";
import {CurveDeployment} from "./curve/CurveDeployment.s.sol";
import {DonationDeployment} from "./donation/DonationDeployment.s.sol";
import {ERC4626Deployment} from "./erc4626/ERC4626Deployment.s.sol";
import {LiquityTroveDeployment} from "./liquity/LiquityTroveDeployment.s.sol";
import {UniswapDeployment} from "./uniswap/UniswapDeployment.s.sol";
import {YearnDeployment} from "./yearn/YearnDeployment.s.sol";

/**
 * A helper script that allow easy deployment of multiple bridges
 * `deployAndListAll()` should contain all bridges with deployment scripts
 * `deployAndListPartial()` should contain the bridges that  should be deployed to devnet
 * The two helpers will probably overlap, but it is not required.
 */
contract AggregateDeployment is Script {
    function deployAndListPartial() public {}

    function deployAndListAll() public {
        (new CurveDeployment()).deployAndList();
        (new YearnDeployment()).deployAndList();
        (new ERC4626Deployment()).deployAndList();
        (new CompoundDeployment()).deployAndList();
        (new DonationDeployment()).deployAndList();
        (new LiquityTroveDeployment()).deployAndList();
        (new UniswapDeployment()).deployAndList();
    }
}
