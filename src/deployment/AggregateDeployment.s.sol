// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {BaseDeployment} from "./base/BaseDeployment.s.sol";
import {IRollupProcessor} from "rollup-encoder/interfaces/IRollupProcessor.sol";
import {DataProvider} from "../aztec/DataProvider.sol";

import {ElementDeployment} from "./element/ElementDeployment.s.sol";
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

    function deployAndListAll() public returns (address) {
        DataProviderDeployment dataProviderDeploy = new DataProviderDeployment();
        dataProviderDeploy.setUp();
        address dataProvider = dataProviderDeploy.deploy();

        emit log("--- Element ---");
        {
            ElementDeployment elementDeployment = new ElementDeployment();
            elementDeployment.setUp();
            address elementBridge = elementDeployment.deployAndList();

            address wrappedDai = 0x3A285cbE492cB172b78E76Cf4f15cb6Fe9f162E4;

            elementDeployment.registerPool(
                elementBridge, 0x71628c66C502F988Fbb9e17081F2bD14e361FAF4, wrappedDai, 1634346845
            );
            elementDeployment.registerPool(
                elementBridge, 0xA47D1251CF21AD42685Cc6B8B3a186a73Dbd06cf, wrappedDai, 1643382446
            );
            elementDeployment.registerPool(
                elementBridge, 0xEdf085f65b4F6c155e13155502Ef925c9a756003, wrappedDai, 1651275535
            );
            elementDeployment.registerPool(
                elementBridge, 0x8fFD1dc7C3eF65f833CF84dbCd15b6Ad7f9C54EC, wrappedDai, 1663361092
            );
            elementDeployment.registerPool(
                elementBridge, 0x7F4A33deE068C4fA012d64677C61519a578dfA35, wrappedDai, 1677243924
            );
        }

        emit log("--- Curve ---");
        {
            CurveDeployment curveDeployment = new CurveDeployment();
            curveDeployment.setUp();
            curveDeployment.deployAndList();
        }

        emit log("--- Yearn ---");
        {
            YearnDeployment yearnDeployment = new YearnDeployment();
            yearnDeployment.setUp();
            yearnDeployment.deployAndList();
        }

        emit log("--- Element 2M ---");
        {
            uint256 element2Id = listBridge(IRollupProcessor(ROLLUP_PROCESSOR).getSupportedBridge(1), 2000000);
            emit log_named_uint("Element 2M bridge address id", element2Id);
        }

        emit log("--- ERC4626 ---");
        {
            ERC4626Deployment erc4626Deployment = new ERC4626Deployment();
            erc4626Deployment.setUp();
            erc4626Bridge = erc4626Deployment.deploy();

            uint256 depositAddressId = listBridge(erc4626Bridge, 300000);
            emit log_named_uint("ERC4626 bridge address id (300k gas)", depositAddressId);
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
            DCADeployment dcaDeployment = new DCADeployment();
            dcaDeployment.setUp();
            dcaDeployment.deployAndList();
        }

        emit log("--- ERC4626 400k and 500k gas configurations ---");
        {
            uint256 depositAddressId = listBridge(erc4626Bridge, 500000);
            emit log_named_uint("ERC4626 bridge address id (500k gas)", depositAddressId);

            depositAddressId = listBridge(erc4626Bridge, 400000);
            emit log_named_uint("ERC4626 bridge address id (400k gas)", depositAddressId);
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

        emit log("--- Liquity 275% CR and 400% CR deployments ---");
        {
            LiquityTroveDeployment liquityTroveDeployment = new LiquityTroveDeployment();
            liquityTroveDeployment.setUp();

            liquityTroveDeployment.deployAndList(275);
            liquityTroveDeployment.deployAndList(400);
        }

        emit log("--- Compound ---");
        {
            ERC4626Lister lister = new ERC4626Lister();
            lister.setUp();

            address erc4626CompoundDai = 0x6D088fe2500Da41D7fA7ab39c76a506D7c91f53b;
            lister.listVault(erc4626Bridge, erc4626CompoundDai);
            uint256 erc4626CDaiId = listAsset(erc4626CompoundDai, 55000);
            emit log_named_uint("ERC4626 compound dai id", erc4626CDaiId);
        }

        emit log("--- Uniswap ---");
        {
            UniswapDeployment uniswapDeployment = new UniswapDeployment();
            uniswapDeployment.setUp();
            uniswapDeployment.deployAndList();
        }

        emit log("--- Set ---");
        {
            address iceth = 0x7C07F7aBe10CE8e33DC6C5aD68FE033085256A84;
            uint256 icethId = listAsset(iceth, 55000);
            emit log_named_uint("Set protocol icEth id", icethId);
        }

        emit log("--- Let anyone deploy ---");
        {
            IRollupProcessor rp = IRollupProcessor(ROLLUP_PROCESSOR);
            if (!rp.allowThirdPartyContracts()) {
                vm.broadcast();
                rp.setAllowThirdPartyContracts(true);
            }
        }

        emit log("--- Data Provider ---");
        {
            dataProviderDeploy.updateNames(dataProvider);
        }

        return dataProvider;
    }

    function deployNew() public {
        // This is performed from a deployer without rights to list.
        bytes[] memory deployData = new bytes[](9);

        emit log("--- Liquity 275% CR and 400% CR deployments ---");
        {
            LiquityTroveDeployment liquityTroveDeployment = new LiquityTroveDeployment();
            liquityTroveDeployment.setUp();

            // Deploy the bridges
            address tb275 = liquityTroveDeployment.deploy(275);
            address tb400 = liquityTroveDeployment.deploy(400);

            // Open the troves
            liquityTroveDeployment.openTrove(tb275);
            liquityTroveDeployment.openTrove(tb400);

            bytes memory listLiquity275Bridge =
                abi.encodeWithSelector(IRollupProcessor.setSupportedBridge.selector, tb275, 700_000);
            bytes memory listLiquity400Bridge =
                abi.encodeWithSelector(IRollupProcessor.setSupportedBridge.selector, tb400, 700_000);
            bytes memory listLUSD = abi.encodeWithSelector(
                IRollupProcessor.setSupportedAsset.selector, 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0, 55_000
            );
            bytes memory listLiquity275Asset =
                abi.encodeWithSelector(IRollupProcessor.setSupportedAsset.selector, tb275, 55_000);
            bytes memory listLiquity400Asset =
                abi.encodeWithSelector(IRollupProcessor.setSupportedAsset.selector, tb400, 55_000);

            deployData[0] = listLiquity275Bridge;
            deployData[1] = listLiquity400Bridge;
            deployData[2] = listLUSD;
            deployData[3] = listLiquity275Asset;
            deployData[4] = listLiquity400Asset;
        }

        emit log("--- Compound ---");
        {
            ERC4626Lister lister = new ERC4626Lister();
            lister.setUp();

            address erc4626CompoundDai = 0x6D088fe2500Da41D7fA7ab39c76a506D7c91f53b;
            bytes memory listCompoundDai =
                abi.encodeWithSelector(IRollupProcessor.setSupportedAsset.selector, erc4626CompoundDai, 55_000);
            deployData[5] = listCompoundDai;
        }

        emit log("--- Uniswap ---");
        {
            UniswapDeployment uniswapDeployment = new UniswapDeployment();
            uniswapDeployment.setUp();
            address uniswapBridge = uniswapDeployment.deploy();

            bytes memory listUniswap =
                abi.encodeWithSelector(IRollupProcessor.setSupportedBridge.selector, uniswapBridge, 500_000);
            bytes memory listLargeUniswap =
                abi.encodeWithSelector(IRollupProcessor.setSupportedBridge.selector, uniswapBridge, 800_000);

            deployData[6] = listUniswap;
            deployData[7] = listLargeUniswap;
        }

        emit log("--- Set ---");
        {
            address iceth = 0x7C07F7aBe10CE8e33DC6C5aD68FE033085256A84;
            bytes memory listIceth = abi.encodeWithSelector(IRollupProcessor.setSupportedAsset.selector, iceth, 55_000);
            deployData[8] = listIceth;
        }

        emit log_named_address("Target", ROLLUP_PROCESSOR);
        emit log_named_bytes("Call 1", deployData[0]);
        emit log_named_bytes("Call 2", deployData[1]);
        emit log_named_bytes("Call 3", deployData[2]);
        emit log_named_bytes("Call 4", deployData[3]);
        emit log_named_bytes("Call 5", deployData[4]);
        emit log_named_bytes("Call 6", deployData[5]);
        emit log_named_bytes("Call 7", deployData[6]);
        emit log_named_bytes("Call 8", deployData[7]);
        emit log_named_bytes("Call 9", deployData[8]);
    }

    function updateDataProvider() public {
        // This should be run after we have already deployed the bridges and assets.
        IRollupProcessor rp = IRollupProcessor(ROLLUP_PROCESSOR);
        DataProvider dataProvider = DataProvider(0x8B2E54fa4398C8f7502f30aC94Cb1f354390c8ab);

        uint256[] memory assetIds = new uint256[](5);
        string[] memory assetNames = new string[](5);
        uint256 assetCount = rp.getSupportedAssetsLength();
        emit log_named_uint("assetCount", assetCount);
        // Start at index 10. The first 10 are already listed.
        for (uint256 i = 10; i <= assetCount; i++) {
            assetIds[i - 10] = i;
            assetNames[i - 10] = IERC20Metadata(rp.getSupportedAsset(i)).symbol();
        }

        // Bridges
        uint256[] memory bridgeIds = new uint256[](4);
        string[] memory bridgeTags = new string[](4);
        uint256 bridgeCount = rp.getSupportedBridgesLength();
        bridgeIds[0] = bridgeCount + 1;
        bridgeIds[1] = bridgeCount + 2;
        bridgeIds[2] = bridgeCount + 3;
        bridgeIds[3] = bridgeCount + 4;
        bridgeTags[0] = "Liquity275_700K";
        bridgeTags[1] = "Liquity400_700K";
        bridgeTags[2] = "Uniswap_500K";
        bridgeTags[3] = "Uniswap_800K";

        vm.prank(dataProvider.owner());
        dataProvider.addAssetsAndBridges(assetIds, assetNames, bridgeIds, bridgeTags);

        DataProviderDeployment dataProviderDeployment = new DataProviderDeployment();
        dataProviderDeployment.readProvider(address(dataProvider));
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
