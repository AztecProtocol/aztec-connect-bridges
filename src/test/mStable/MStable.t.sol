// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {AztecTypes} from "./../../aztec/AztecTypes.sol";
import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {MStableBridge} from "./../../bridges/mStable/MStableBridge.sol";

contract MStableTest is Test {
    RollupProcessor private rollupProcessor;
    DefiBridgeProxy private defiBridgeProxy;

    MStableBridge private mStableBridge;

    mapping(string => IERC20) private tokens;

    function setUp() public {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));

        mStableBridge = new MStableBridge(address(rollupProcessor));

        tokens["DAI"] = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
        tokens["imUSD"] = IERC20(0x30647a72Dc82d7Fbb1123EA74716aB8A317Eac19);

        rollupProcessor.setBridgeGasLimit(address(mStableBridge), 900000);
    }

    function testMStableIMUSDToDai() public {
        uint256 depositAmount = 1 * 10**21;

        deal(address(tokens["DAI"]), address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;

        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(tokens["imUSD"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = rollupProcessor.convert(
            address(mStableBridge),
            inputAsset,
            empty,
            outputAsset,
            empty,
            depositAmount,
            1,
            100
        );

        uint256 newRollupimUSD = tokens["imUSD"].balanceOf(address(rollupProcessor));
        uint256 newRollupDai = tokens["DAI"].balanceOf(address(rollupProcessor));

        assertEq(outputValueA, newRollupimUSD, "Balances must match");

        assertEq(outputValueB, 0, "Should have no output value b");

        assertEq(newRollupDai, 0, "All Dai should be spent");

        assertTrue(!isAsync, "Should be sync");
    }

    function testMStableDaiToImusd() public {
        uint256 daiDepositAmount = 1000 * 10**18;

        deal(address(tokens["DAI"]), address(rollupProcessor), daiDepositAmount);

        AztecTypes.AztecAsset memory empty;

        AztecTypes.AztecAsset memory imUSD = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(tokens["imUSD"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory dai = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(tokens["DAI"]),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (uint256 imUSDAmount, , ) = rollupProcessor.convert(
            address(mStableBridge),
            dai,
            empty,
            imUSD,
            empty,
            daiDepositAmount,
            1,
            100
        );

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = rollupProcessor.convert(
            address(mStableBridge),
            imUSD,
            empty,
            dai,
            empty,
            imUSDAmount,
            2,
            100
        );

        uint256 newRollupimUSD = tokens["imUSD"].balanceOf(address(rollupProcessor));
        uint256 newRollupDai = tokens["DAI"].balanceOf(address(rollupProcessor));

        assertEq(outputValueA, newRollupDai, "Balances must match");

        assertEq(outputValueB, 0, "Should have no output value b");

        assertEq(newRollupimUSD, 0, "All Dai should be spent");

        assertTrue(!isAsync, "Should be sync");
    }
}
