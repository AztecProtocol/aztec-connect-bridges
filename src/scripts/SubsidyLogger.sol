// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {BridgeBase} from "../bridges/base/BridgeBase.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ISubsidy} from "../aztec/interfaces/ISubsidy.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

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

    AztecTypes.AztecAsset internal emptyAsset;
    // @dev if set to true only subsidies which need to be funded get displayed
    bool public onlyEmpty = false;

    function setUp() public {
        onlyEmpty = vm.envBool("ONLY_EMPTY");
        emit log_named_uint("Hours for full subsidy", FULL_SUBSIDY_TIME);
        emit log_named_decimal_uint("Gas price used in gwei", ESTIMATION_BASE_FEE, 9);
    }

    function logSubsidies() public {
        logERC4626Subsidies();
        logYearnSubsidies();
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
        // bridge address asset combination gas usage subsidy
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
}
