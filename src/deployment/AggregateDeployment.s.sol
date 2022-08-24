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

contract AggregateDeployment is Script {
    function deployAndListAll() public {
        (new CompoundDeployment()).deployAndList();
        (new CurveDeployment()).deployAndList();
        (new DonationDeployment()).deployAndList();
        (new ERC4626Deployment()).deployAndList();
        (new LiquityTroveDeployment()).deployAndList();
        (new UniswapDeployment()).deployAndList();
        (new YearnDeployment()).deployAndList();
    }
}
