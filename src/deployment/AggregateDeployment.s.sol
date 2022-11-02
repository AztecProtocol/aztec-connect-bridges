// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BaseDeployment} from "./base/BaseDeployment.s.sol";
import {IRollupProcessor} from "rollup-encoder/interfaces/IRollupProcessor.sol";
import {DataProvider} from "../aztec/DataProvider.sol";

import {CurveDeployment} from "./curve/CurveDeployment.s.sol";
import {DonationDeployment} from "./donation/DonationDeployment.s.sol";
import {ERC4626Deployment} from "./erc4626/ERC4626Deployment.s.sol";
import {ERC4626Lister} from "./erc4626/ERC4626Lister.s.sol";
import {LiquityTroveDeployment} from "./liquity/LiquityTroveDeployment.s.sol";
import {UniswapDeployment} from "./uniswap/UniswapDeployment.s.sol";
import {YearnDeployment} from "./yearn/YearnDeployment.s.sol";
import {DCADeployment} from "./dca/DCADeployment.s.sol";
import {AngleSLPDeployment} from "./angle/AngleSLPDeployment.s.sol";
import {DataProviderDeployment} from "./dataprovider/DataProviderDeployment.s.sol";
import {CurveStethLpDeployment} from "./curve/CurveStethLpDeployment.s.sol";

/**
 * A helper script that allow easy deployment of multiple bridges
 */
contract AggregateDeployment is BaseDeployment {
    address internal erc4626Bridge;

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
            erc4626Bridge = deploy.deployAndList();
        }

        emit log("--- Euler ---");
        {
            ERC4626Lister lister = new ERC4626Lister();
            lister.setUp();

            address erc4626EulerWETH = 0x3c66B18F67CA6C1A71F829E2F6a0c987f97462d0;
            lister.listVault(erc4626Bridge, erc4626EulerWETH);
            uint256 weWethAssetId = listAsset(erc4626EulerWETH, 55000);
            emit log_named_uint("ERC4626 euler weth id", weWethAssetId);

            address erc4626EulerWSTETH = 0x60897720AA966452e8706e74296B018990aEc527;
            lister.listVault(erc4626Bridge, erc4626EulerWSTETH);
            uint256 wewstEthAssetId = listAsset(erc4626EulerWSTETH, 55000);
            emit log_named_uint("ERC4626 euler wstEth id", wewstEthAssetId);

            address erc4626EulerDai = 0x4169Df1B7820702f566cc10938DA51F6F597d264;
            lister.listVault(erc4626Bridge, erc4626EulerDai);
            uint256 wedaiAssetId = listAsset(erc4626EulerDai, 55000);
            emit log_named_uint("ERC4626 euler dai id", wedaiAssetId);
        }

        emit log("--- DCA ---");
        {
            DCADeployment deploy = new DCADeployment();
            deploy.setUp();
            deploy.deployAndList();
        }

        emit log("--- Liquity CR 250%---");
        {
            LiquityTroveDeployment deploy = new LiquityTroveDeployment();
            deploy.setUp();
            deploy.deployAndList(250);
        }

        emit log("--- Liquity CR 350%---");
        {
            LiquityTroveDeployment deploy = new LiquityTroveDeployment();
            deploy.setUp();
            deploy.deployAndList(350);
        }

        emit log("--- AAVE v2 ---");
        {
            ERC4626Lister lister = new ERC4626Lister();
            lister.setUp();

            address erc4626AaveV2Dai = 0xbcb91e0B4Ad56b0d41e0C168E3090361c0039abC;
            lister.listVault(erc4626Bridge, erc4626AaveV2Dai);
            uint256 erc4626AaveV2DaiId = listAsset(erc4626AaveV2Dai, 55000);
            emit log_named_uint("ERC4626 aave v2 dai id", erc4626AaveV2DaiId);

            address erc4626AaveV2WETH = 0xc21F107933612eCF5677894d45fc060767479A9b;
            lister.listVault(erc4626Bridge, erc4626AaveV2WETH);
            uint256 erc4626AaveV2WETHId = listAsset(erc4626AaveV2WETH, 55000);
            emit log_named_uint("ERC4626 aave v2 weth id", erc4626AaveV2WETHId);
        }
    }

    function bogota() public {
        deployAndListAll();

        emit log("--- Donation ---");
        {
            DonationDeployment deploy = new DonationDeployment();
            deploy.setUp();
            deploy.deployAndList();
        }

        emit log("--- Angle ---");
        {
            AngleSLPDeployment deploy = new AngleSLPDeployment();
            deploy.setUp();
            deploy.deployAndList();
        }

        emit log("--- Uniswap --");
        {
            UniswapDeployment deploy = new UniswapDeployment();
            deploy.setUp();
            deploy.deployAndList();
        }

        emit log("--- Liquity ---");
        {
            LiquityTroveDeployment deploy = new LiquityTroveDeployment();
            deploy.setUp();
            deploy.deployAndList(250);
        }

        emit log("--- Curve steth lp ---");
        {
            CurveStethLpDeployment deploy = new CurveStethLpDeployment();
            deploy.setUp();
            deploy.deployAndList();
        }

        IRollupProcessor rp = IRollupProcessor(ROLLUP_PROCESSOR);
        vm.broadcast();
        rp.setAllowThirdPartyContracts(true);

        emit log("--- data provider ---");
        {
            DataProviderDeployment deploy = new DataProviderDeployment();
            deploy.setUp();
            address provider = deploy.deployAndListMany();

            uint256[] memory assetIds = new uint256[](4);
            string[] memory assetTags = new string[](4);

            assetIds[0] = 8;
            assetIds[1] = 9;
            assetIds[2] = 10;
            assetIds[3] = 11;
            assetTags[0] = "sandai_eur";
            assetTags[1] = "sanweth_eur";
            assetTags[2] = "lusd";
            assetTags[3] = "stecrv";

            uint256[] memory bridgeAddressIds = new uint256[](7);
            string[] memory bridgeTags = new string[](7);
            bridgeAddressIds[0] = 12;
            bridgeTags[0] = "DonationBridge";
            bridgeAddressIds[1] = 13;
            bridgeTags[1] = "AngleSLPBridgeDeposit";
            bridgeAddressIds[2] = 14;
            bridgeTags[2] = "AngleSLPBridgeWithdraw";
            bridgeAddressIds[3] = 15;
            bridgeTags[3] = "UniswapBridge500K";
            bridgeAddressIds[4] = 16;
            bridgeTags[4] = "UniswapBridge800K";
            bridgeAddressIds[5] = 17;
            bridgeTags[5] = "LiquityTroveBridge";
            bridgeAddressIds[6] = 18;
            bridgeTags[6] = "CurveStEthLpBridge";

            vm.broadcast();
            DataProvider(provider).addAssetsAndBridges(assetIds, assetTags, bridgeAddressIds, bridgeTags);
            deploy.readProvider(provider);
        }

        // readStats();
    }

    function readStats() public {
        emit log("--- Stats for the Rollup ---");
        IRollupProcessor rp = IRollupProcessor(ROLLUP_PROCESSOR);

        if (rp.allowThirdPartyContracts()) {
            emit log("Third parties can deploy bridges");
        } else {
            emit log("Third parties cannot deploy bridges");
        }

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
