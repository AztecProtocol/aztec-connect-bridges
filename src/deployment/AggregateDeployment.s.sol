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
import {DCADeployment} from "./dca/DCADeployment.s.sol";

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

        emit log("--- Element 2M ---");
        {
            uint256 element2Id = listBridge(IRollupProcessor(ROLLUP_PROCESSOR).getSupportedBridge(1), 2000000);
            emit log_named_uint("Element 2M bridge address id", element2Id);
        }

        emit log("--- ERC4626 ---");
        {
            ERC4626Deployment deploy = new ERC4626Deployment();
            deploy.setUp();
            deploy.deployAndList();
        }

        emit log("--- Euler ---");
        {
            address erc4626EulerWETH = 0x3c66B18F67CA6C1A71F829E2F6a0c987f97462d0;
            uint256 weWethAssetId = listAsset(erc4626EulerWETH, 55000);
            emit log_named_uint("ERC4626 euler weth id", weWethAssetId);

            address erc4626EulerWSTETH = 0x60897720AA966452e8706e74296B018990aEc527;
            uint256 wewstEthAssetId = listAsset(erc4626EulerWSTETH, 55000);
            emit log_named_uint("ERC4626 euler wstEth id", wewstEthAssetId);

            address erc4626EulerDai = 0x4169Df1B7820702f566cc10938DA51F6F597d264;
            uint256 wedaiAssetId = listAsset(erc4626EulerDai, 55000);
            emit log_named_uint("ERC4626 euler dai id", wedaiAssetId);
        }

        emit log("--- DCA ---");
        {
            DCADeployment deploy = new DCADeployment();
            deploy.setUp();
            deploy.deployAndList();
        }

        readStats();
    }

    function readStats() public {
        IRollupProcessor rp = IRollupProcessor(ROLLUP_PROCESSOR);

        uint256 assetCount = assetLength();
        emit log_named_uint("Assets", assetCount + 1);
        for (uint256 i = 0; i <= assetCount; i++) {
            string memory symbol = i > 0 ? IERC20Metadata(rp.getSupportedAsset(i)).symbol() : "Eth";
            uint256 gas = i > 0 ? rp.assetGasLimits(i) : 30000;
            emit log_named_string(
                string(abi.encodePacked("  Asset ", Strings.toString(i))),
                string(abi.encodePacked(symbol, ", ", Strings.toString(gas)))
            );
        }

        uint256 bridgeCount = bridgesLength();
        emit log_named_uint("Bridges", bridgeCount);
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
