// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {BridgeBase} from "../bridges/base/BridgeBase.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ISubsidy} from "../aztec/interfaces/ISubsidy.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {UniswapBridge} from "../bridges/uniswap/UniswapBridge.sol";

/**
 * @title Script which logs either all subsidized or non-subsidized bridges
 * @author Aztec team
 * @dev execute with: ONLY_EMPTY=true && forge script src/scripts/SubsidyLogger.sol:SubsidyLogger --fork-url $RPC --sig "logSubsidies()"
 */
contract SubsidyLogger is Test {
    ISubsidy public constant SUBSIDY = ISubsidy(0xABc30E831B5Cc173A9Ed5941714A7845c909e7fA);
    // @dev A time period denominated in hours indicating after what time a call is fully subsidized
    uint256 public constant FULL_SUBSIDY_TIME = 36;
    uint256 public constant ESTIMATION_BASE_FEE = 2e10; // 20 gwei

    address[] private erc4626Shares = [
        0x3c66B18F67CA6C1A71F829E2F6a0c987f97462d0, // ERC4626-Wrapped Euler WETH (weWETH)
        0x4169Df1B7820702f566cc10938DA51F6F597d264, //  ERC4626-Wrapped Euler DAI (weDAI)
        0x60897720AA966452e8706e74296B018990aEc527, //  ERC4626-Wrapped Euler wstETH (wewstETH)
        0xbcb91e0B4Ad56b0d41e0C168E3090361c0039abC, //  ERC4626-Wrapped AAVE V2 DAI (wa2DAI)
        0xc21F107933612eCF5677894d45fc060767479A9b //  ERC4626-Wrapped AAVE V2 WETH (wa2WETH)
    ];

    string[] private erc4626Tags = [
        "ERC4626-Wrapped Euler WETH (weWETH)",
        "ERC4626-Wrapped Euler DAI (weDAI)",
        "ERC4626-Wrapped Euler wstETH (wewstETH)",
        "ERC4626-Wrapped AAVE V2 DAI (wa2DAI)",
        "ERC4626-Wrapped AAVE V2 WETH (wa2WETH)"
    ];

    // @dev if set to true only subsidies which need to be funded get displayed
    bool public onlyEmpty = false;

    AztecTypes.AztecAsset internal emptyAsset;
    AztecTypes.AztecAsset internal ethAsset;
    AztecTypes.AztecAsset internal icEthAsset;

    function setUp() public {
        onlyEmpty = vm.envBool("ONLY_EMPTY");
        ethAsset = AztecTypes.AztecAsset({id: 0, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.ETH});
        icEthAsset = AztecTypes.AztecAsset({
            id: 14,
            erc20Address: 0x7C07F7aBe10CE8e33DC6C5aD68FE033085256A84,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        emit log_named_uint("Hours for full subsidy", FULL_SUBSIDY_TIME);
        emit log_named_decimal_uint("Gas price used in gwei", ESTIMATION_BASE_FEE, 9);
    }

    function logSubsidies() public {
        logERC4626Subsidies();
        logYearnSubsidies();
        logLiquityTroveSubsidies(0x998650bf01A6424F9B11debd85a29090906cB559); // TB-275
        logLiquityTroveSubsidies(0x646Df2Dc98741a0Ab5798DeAC6Fc62411dA41D96); // TB-400
        logUniswapSubsidies(ethAsset, icEthAsset);
    }

    function logERC4626Subsidies() public {
        BridgeBase bridge = BridgeBase(0x3578D6D5e1B4F07A48bb1c958CBfEc135bef7d98);

        emit log_string("\n");
        emit log_string("=========== ERC4626 Bridge =============");
        emit log_named_address("Bridge address", address(bridge));

        for (uint256 i = 0; i < erc4626Shares.length; i++) {
            address share = erc4626Shares[i];
            address asset = IERC4626(share).asset();

            AztecTypes.AztecAsset memory shareAsset = AztecTypes.AztecAsset({
                id: 0, // ID is not used when computing criteria and for this reason can be incorrect
                erc20Address: share,
                assetType: AztecTypes.AztecAssetType.ERC20
            });
            AztecTypes.AztecAsset memory assetAsset = AztecTypes.AztecAsset({
                id: 0, // ID is not used when computing criteria and for this reason can be incorrect
                erc20Address: asset,
                assetType: AztecTypes.AztecAssetType.ERC20
            });

            uint256 enterCriteria = bridge.computeCriteria(assetAsset, emptyAsset, shareAsset, emptyAsset, 0);
            uint256 exitCriteria = bridge.computeCriteria(shareAsset, emptyAsset, assetAsset, emptyAsset, 0);

            ISubsidy.Subsidy memory enterSubsidy = SUBSIDY.getSubsidy(address(bridge), enterCriteria);
            ISubsidy.Subsidy memory exitSubsidy = SUBSIDY.getSubsidy(address(bridge), exitCriteria);

            if (enterSubsidy.available == 0 || !onlyEmpty) {
                uint256 gasPerMinute = enterSubsidy.gasUsage / (FULL_SUBSIDY_TIME * 60);
                emit log_string("========================");
                emit log_string(erc4626Tags[i]);
                emit log_named_address("share", share);
                emit log_named_uint("enterCriteria", enterCriteria);
                emit log_named_uint("enterCriteria available", enterSubsidy.available);
                emit log_named_uint("enterCriteria gasUsage", enterSubsidy.gasUsage);
                emit log_named_uint("recommended minGasPerMinute", gasPerMinute);
                uint256 costOfMonth = enterSubsidy.gasUsage * (24 * 30) * ESTIMATION_BASE_FEE / FULL_SUBSIDY_TIME;
                emit log_named_decimal_uint("cost of fully subsidizing for a month", costOfMonth, 18);
            }

            if (exitSubsidy.available == 0 || !onlyEmpty) {
                uint256 gasPerMinute = exitSubsidy.gasUsage / (FULL_SUBSIDY_TIME * 60);
                emit log_string("========================");
                emit log_string(erc4626Tags[i]);
                emit log_named_address("share", share);
                emit log_named_uint("exitCriteria", exitCriteria);
                emit log_named_uint("exitCriteria available", exitSubsidy.available);
                emit log_named_uint("exitCriteria gasUsage", exitSubsidy.gasUsage);
                emit log_named_uint("recommended minGasPerMinute", gasPerMinute);
                uint256 costOfMonth = exitSubsidy.gasUsage * (24 * 30) * ESTIMATION_BASE_FEE / FULL_SUBSIDY_TIME;
                emit log_named_decimal_uint("cost of fully subsidizing for a month", costOfMonth, 18);
            }
        }

        emit log_string("========================");
    }

    function logYearnSubsidies() public {
        BridgeBase bridge = BridgeBase(0xE71A50a78CcCff7e20D8349EED295F12f0C8C9eF);

        emit log_string("\n");
        emit log_string("=========== Yearn Bridge =============");
        emit log_named_address("Bridge address", address(bridge));

        uint256 enterCriteria = 0;
        uint256 exitCriteria = 1;

        ISubsidy.Subsidy memory enterSubsidy = SUBSIDY.getSubsidy(address(bridge), enterCriteria);
        ISubsidy.Subsidy memory exitSubsidy = SUBSIDY.getSubsidy(address(bridge), exitCriteria);

        if (enterSubsidy.available == 0 || !onlyEmpty) {
            uint256 gasPerMinute = enterSubsidy.gasUsage / (FULL_SUBSIDY_TIME * 60);
            emit log_string("========================");
            emit log_named_uint("enterCriteria", enterCriteria);
            emit log_named_uint("enterCriteria available", enterSubsidy.available);
            emit log_named_uint("enterCriteria gasUsage", enterSubsidy.gasUsage);
            emit log_named_uint("recommended minGasPerMinute", gasPerMinute);
            uint256 costOfMonth = enterSubsidy.gasUsage * (24 * 30) * ESTIMATION_BASE_FEE / FULL_SUBSIDY_TIME;
            emit log_named_decimal_uint("cost of fully subsidizing for a month", costOfMonth, 18);
        }

        if (exitSubsidy.available == 0 || !onlyEmpty) {
            uint256 gasPerMinute = exitSubsidy.gasUsage / (FULL_SUBSIDY_TIME * 60);
            emit log_string("========================");
            emit log_named_uint("exitCriteria", exitCriteria);
            emit log_named_uint("exitCriteria available", exitSubsidy.available);
            emit log_named_uint("exitCriteria gasUsage", exitSubsidy.gasUsage);
            emit log_named_uint("recommended minGasPerMinute", gasPerMinute);
            uint256 costOfMonth = exitSubsidy.gasUsage * (24 * 30) * ESTIMATION_BASE_FEE / FULL_SUBSIDY_TIME;
            emit log_named_decimal_uint("cost of fully subsidizing for a month", costOfMonth, 18);
        }

        emit log_string("========================");
    }

    function logLiquityTroveSubsidies(address _bridge) public {
        emit log_string("\n");
        emit log_string("=========== Trove Bridge =============");
        emit log_named_address("Bridge address", _bridge);
        emit log_named_string("Bridge symbol", IERC20Metadata(_bridge).symbol());

        uint256 enterCriteria = 0;
        uint256 exitCriteria = 1;

        ISubsidy.Subsidy memory enterSubsidy = SUBSIDY.getSubsidy(_bridge, enterCriteria);
        ISubsidy.Subsidy memory exitSubsidy = SUBSIDY.getSubsidy(_bridge, exitCriteria);

        if (enterSubsidy.available == 0 || !onlyEmpty) {
            uint256 gasPerMinute = enterSubsidy.gasUsage / (FULL_SUBSIDY_TIME * 60);
            emit log_string("========================");
            emit log_named_uint("enterCriteria", enterCriteria);
            emit log_named_uint("enterCriteria available", enterSubsidy.available);
            emit log_named_uint("enterCriteria gasUsage", enterSubsidy.gasUsage);
            emit log_named_uint("recommended minGasPerMinute", gasPerMinute);
            uint256 costOfMonth = enterSubsidy.gasUsage * (24 * 30) * ESTIMATION_BASE_FEE / FULL_SUBSIDY_TIME;
            emit log_named_decimal_uint("cost of fully subsidizing for a month", costOfMonth, 18);
        }

        if (exitSubsidy.available == 0 || !onlyEmpty) {
            uint256 gasPerMinute = exitSubsidy.gasUsage / (FULL_SUBSIDY_TIME * 60);
            emit log_string("========================");
            emit log_named_uint("exitCriteria", exitCriteria);
            emit log_named_uint("exitCriteria available", exitSubsidy.available);
            emit log_named_uint("exitCriteria gasUsage", exitSubsidy.gasUsage);
            emit log_named_uint("recommended minGasPerMinute", gasPerMinute);
            uint256 costOfMonth = exitSubsidy.gasUsage * (24 * 30) * ESTIMATION_BASE_FEE / FULL_SUBSIDY_TIME;
            emit log_named_decimal_uint("cost of fully subsidizing for a month", costOfMonth, 18);
        }

        emit log_string("========================");
    }

    function logUniswapSubsidies(AztecTypes.AztecAsset memory _inputAssetA, AztecTypes.AztecAsset memory _outputAssetA)
        public
    {
        // For some reason when I use the actual deployment of the bridge on mainnet I get zero criteria when calling
        // computeCriteria. I don't know why and don't want to spend time on it now since we are not setting u
        // the subsidy now. When I use a new deployment of the bridge here it works fine. Probably some issue with
        // Foundry setting.
        // BridgeBase bridge = BridgeBase(0x5594808e8A7b44da9D2382E6d72ad50a3e2571E0);
        UniswapBridge bridge = new UniswapBridge(0xFF1F2B4ADb9dF6FC8eAFecDcbF96A2B351680455);

        emit log_string("\n");
        emit log_string("=========== Uniswap Bridge =============");
        emit log_named_address("Bridge address", address(bridge));
        emit log_named_address("Input asset", _inputAssetA.erc20Address);
        emit log_named_address("Output asset", _outputAssetA.erc20Address);

        uint256 enterCriteria = bridge.computeCriteria(_inputAssetA, emptyAsset, _outputAssetA, emptyAsset, 0);
        uint256 exitCriteria = bridge.computeCriteria(_outputAssetA, emptyAsset, _inputAssetA, emptyAsset, 0);

        ISubsidy.Subsidy memory enterSubsidy = SUBSIDY.getSubsidy(address(bridge), enterCriteria);
        ISubsidy.Subsidy memory exitSubsidy = SUBSIDY.getSubsidy(address(bridge), exitCriteria);

        if (enterSubsidy.available == 0 || !onlyEmpty) {
            uint256 gasPerMinute = enterSubsidy.gasUsage / (FULL_SUBSIDY_TIME * 60);
            emit log_string("========================");
            emit log_named_uint("enterCriteria", enterCriteria);
            emit log_named_uint("enterCriteria available", enterSubsidy.available);
            emit log_named_uint("enterCriteria gasUsage", enterSubsidy.gasUsage);
            emit log_named_uint("recommended minGasPerMinute", gasPerMinute);
            uint256 costOfMonth = enterSubsidy.gasUsage * (24 * 30) * ESTIMATION_BASE_FEE / FULL_SUBSIDY_TIME;
            emit log_named_decimal_uint("cost of fully subsidizing for a month", costOfMonth, 18);
        }

        if (exitSubsidy.available == 0 || !onlyEmpty) {
            uint256 gasPerMinute = exitSubsidy.gasUsage / (FULL_SUBSIDY_TIME * 60);
            emit log_string("========================");
            emit log_named_uint("exitCriteria", exitCriteria);
            emit log_named_uint("exitCriteria available", exitSubsidy.available);
            emit log_named_uint("exitCriteria gasUsage", exitSubsidy.gasUsage);
            emit log_named_uint("recommended minGasPerMinute", gasPerMinute);
            uint256 costOfMonth = exitSubsidy.gasUsage * (24 * 30) * ESTIMATION_BASE_FEE / FULL_SUBSIDY_TIME;
            emit log_named_decimal_uint("cost of fully subsidizing for a month", costOfMonth, 18);
        }

        emit log_string("========================");
    }
}
