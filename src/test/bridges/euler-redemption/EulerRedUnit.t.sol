// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";

import {IWETH} from "../../../interfaces/IWETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {EulerRedemptionBridge} from "../../../bridges/euler-redemption/EulerRedemptionBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";

import {ERC4626Migrator} from "euler-redemption/ERC4626Migrator.sol";

// @notice The purpose of this test is to directly test convert functionality of the bridge.
contract EulerUnitTest is BridgeTestBase {
    address private rollupProcessor;
    EulerRedemptionBridge private bridge;

    IWETH public constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    ERC20 public constant DAI = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 public constant USDC = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 public constant WSTETH = ERC20(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    IERC4626 public constant WEDAI = IERC4626(0x4169Df1B7820702f566cc10938DA51F6F597d264);
    IERC4626 public constant WEWETH = IERC4626(0x3c66B18F67CA6C1A71F829E2F6a0c987f97462d0);
    IERC4626 public constant WEWSTETH = IERC4626(0x60897720AA966452e8706e74296B018990aEc527);

    ERC20[3] public assets = [ERC20(address(WETH)), DAI, WSTETH];
    IERC4626[3] public weAssets = [WEWETH, WEDAI, WEWSTETH];
    ERC4626Migrator[] public migrators;

    function receiveEthFromBridge(uint256 _interactionNonce) external payable {}

    function setUp() public {
        rollupProcessor = address(this);

        // Deploy migrators
        migrators.push(new ERC4626Migrator(ERC20(address(WEWETH))));
        migrators.push(new ERC4626Migrator(ERC20(address(WEDAI))));
        migrators.push(new ERC4626Migrator(ERC20(address(WEWSTETH))));

        // Deploy bridge
        bridge = new EulerRedemptionBridge(
            rollupProcessor,
            address(migrators[0]),
            address(migrators[1]),
            address(migrators[2])
        );

        deal(address(WETH), address(this), 0);
        deal(address(DAI), address(this), 0);
        deal(address(WSTETH), address(this), 0);

        vm.label(address(bridge), "EulerRedemptionBridge");
        vm.label(address(WEWETH), "WEWETH");
        vm.label(address(WEDAI), "WEDAI");
        vm.label(address(WEWSTETH), "WEWSTETH");
        vm.label(address(migrators[0]), "WETH_MIGRATOR");
        vm.label(address(migrators[1]), "DAI_MIGRATOR");
        vm.label(address(migrators[2]), "WSTETH_MIGRATOR");
        vm.label(0xE592427A0AEce92De3Edee1F18E0157C05861564, "UNISWAP_ROUTER");
        vm.label(0xBA12222222228d8Ba445958a75a0704d566BF2C8, "BALANCER_VAULT");
    }

    function testFuzzExit(
        uint256 _asset,
        uint256 _wethRedeemable,
        uint256 _daiRedeemable,
        uint256 _usdcRedeemable,
        uint256 _exitAmount
    ) public {
        uint256 assetIndex = bound(_asset, 0, 2);
        ERC20 asset = assets[assetIndex];
        IERC4626 weAsset = weAssets[assetIndex];

        uint256 wethRedeemable = bound(_wethRedeemable, 1e18, 1e22);
        uint256 daiRedeemable = bound(_daiRedeemable, 1e18, 1e24);
        uint256 usdcRedeemable = bound(_usdcRedeemable, 1e6, 1e12);
        uint256 exitAmount = bound(_exitAmount, 1e6, weAsset.balanceOf(address(ROLLUP_PROCESSOR)));

        // Impersonate being the actual rollup for funds here. To avoid having to deal with updating totalSupply ourselves.AztecTypes
        vm.prank(address(ROLLUP_PROCESSOR));
        weAsset.transfer(address(bridge), exitAmount);

        _migratorAmounts(migrators[assetIndex], wethRedeemable, daiRedeemable, usdcRedeemable);
        AztecTypes.AztecAsset memory aztecInputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(weAsset));
        AztecTypes.AztecAsset memory aztecExitAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        if (assetIndex > 0) {
            aztecExitAsset = ROLLUP_ENCODER.getRealAztecAsset(address(asset));
        }

        uint256 ethBefore = address(this).balance;

        (uint256 a,,) =
            bridge.convert(aztecInputAsset, emptyAsset, aztecExitAsset, emptyAsset, exitAmount, 0, 0, address(0));

        // We need to actually know that something should be returned. The correct could very well be to return 0.
        assertGt(a, 0, "Invalid amount received");

        if (assetIndex == 0) {
            assertEq(a, address(this).balance - ethBefore, "Invalid eth amount received");
        } else {
            asset.transferFrom(address(bridge), address(this), a);
            assertEq(a, asset.balanceOf(address(this)), "Invalid asset amount received");
        }

        assertEq(WETH.balanceOf(address(bridge)), 0, "Bridge should have no eth");
        assertEq(DAI.balanceOf(address(bridge)), 0, "Bridge should have no dai");
        assertEq(USDC.balanceOf(address(bridge)), 0, "Bridge should have no usdc");

        // Then we want to ensure that we are receiving more of the planned asset, than we could get directly (e.g., that something was swapped)
        // We need there to a be a swap of >1$ or so before check really makes sense. Otherwise we could easily just be rounding down.
        if (assetIndex == 0) {
            uint256 stableValueExpected = (daiRedeemable * exitAmount) / weAsset.totalSupply()
                + (usdcRedeemable * exitAmount * 1e12) / weAsset.totalSupply();
            if (stableValueExpected > 1e18) {
                assertGt(a, (wethRedeemable * exitAmount) / weAsset.totalSupply(), "No extra eth from swaps");
            }
        } else if (assetIndex == 1) {
            if (
                (wethRedeemable * exitAmount) / weAsset.totalSupply() > 1e15
                    || (usdcRedeemable * exitAmount * 1e12) / weAsset.totalSupply() > 1e18
            ) {
                assertGt(a, (daiRedeemable * exitAmount) / weAsset.totalSupply(), "No extra dai from swaps");
            }
        }
    }

    function testOnlyOneRedeemableAsset() public {
        for (uint256 i = 0; i < 3; i++) {
            for (uint256 j = 0; j < 3; j++) {
                ERC20 asset = assets[i];
                IERC4626 weAsset = weAssets[i];

                vm.deal(address(this), 0);
                deal(address(WSTETH), address(this), 0);
                deal(address(DAI), address(this), 0);

                deal(address(WETH), address(migrators[i]), 0);
                deal(address(DAI), address(migrators[i]), 0);
                deal(address(USDC), address(migrators[i]), 0);

                assertEq(WETH.balanceOf(address(migrators[i])), 0, "migrator should have no eth");
                assertEq(DAI.balanceOf(address(migrators[i])), 0, "migrator should have no dai");
                assertEq(USDC.balanceOf(address(migrators[i])), 0, "migrator should have no usdc");

                uint256 wethRedeemable = j == 0 ? 100e18 : 0;
                uint256 daiRedeemable = j == 1 ? 100e18 : 0;
                uint256 usdcRedeemable = j == 2 ? 100e6 : 0;
                uint256 exitAmount = bound(1e18, 1e6, weAsset.balanceOf(address(ROLLUP_PROCESSOR)));

                vm.prank(address(ROLLUP_PROCESSOR));
                weAsset.transfer(address(bridge), exitAmount);

                _migratorAmounts(migrators[i], wethRedeemable, daiRedeemable, usdcRedeemable);
                assertEq(
                    WETH.balanceOf(address(migrators[i])), j == 0 ? wethRedeemable : 0, "migrator should have no eth"
                );
                assertEq(
                    DAI.balanceOf(address(migrators[i])), j == 1 ? daiRedeemable : 0, "migrator should have no dai"
                );
                assertEq(
                    USDC.balanceOf(address(migrators[i])), j == 2 ? usdcRedeemable : 0, "migrator should have no usdc"
                );

                AztecTypes.AztecAsset memory aztecInputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(weAsset));
                AztecTypes.AztecAsset memory aztecExitAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
                if (i > 0) {
                    aztecExitAsset = ROLLUP_ENCODER.getRealAztecAsset(address(asset));
                }

                (uint256 a,,) = bridge.convert(
                    aztecInputAsset, emptyAsset, aztecExitAsset, emptyAsset, exitAmount, 0, 0, address(0)
                );
                assertGt(a, 0, "Invalid amount received");

                // For non eth output, need to pull it.
                if (aztecExitAsset.erc20Address != address(0)) {
                    asset.transferFrom(address(bridge), address(this), a);
                }

                assertEq(address(this).balance, i == 0 ? a : 0, "Self should have no eth");
                assertEq(DAI.balanceOf(address(this)), i == 1 ? a : 0, "Self should have no dai");
                assertEq(WSTETH.balanceOf(address(this)), i == 2 ? a : 0, "Self should have no wsteth");

                assertEq(WETH.balanceOf(address(bridge)), 0, "Bridge should have no eth");
                assertEq(DAI.balanceOf(address(bridge)), 0, "Bridge should have no dai");
                assertEq(USDC.balanceOf(address(bridge)), 0, "Bridge should have no usdc");
            }
        }
    }

    function testFuzzSlippageExceeded(
        uint256 _asset,
        uint256 _wethRedeemable,
        uint256 _daiRedeemable,
        uint256 _usdcRedeemable,
        uint256 _exitAmount
    ) public {
        // Set slippage to expect very large profit from swap such that it intentionally fails.

        uint256 assetIndex = bound(_asset, 0, 2);
        ERC20 asset = assets[assetIndex];
        IERC4626 weAsset = weAssets[assetIndex];

        uint256 wethRedeemable = bound(_wethRedeemable, 1e18, 1e20);
        uint256 daiRedeemable = bound(_daiRedeemable, 1e18, 1e20);
        uint256 usdcRedeemable = bound(_usdcRedeemable, 1e6, 1e8);
        uint256 exitAmount = bound(_exitAmount, 1e6, weAsset.balanceOf(address(ROLLUP_PROCESSOR)));

        // Impersonate being the actual rollup for funds here. To avoid having to deal with updating totalSupply ourselves.AztecTypes
        vm.prank(address(ROLLUP_PROCESSOR));
        weAsset.transfer(address(bridge), exitAmount);

        _migratorAmounts(migrators[assetIndex], wethRedeemable, daiRedeemable, usdcRedeemable);
        AztecTypes.AztecAsset memory aztecInputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(weAsset));
        AztecTypes.AztecAsset memory aztecExitAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        if (assetIndex > 0) {
            aztecExitAsset = ROLLUP_ENCODER.getRealAztecAsset(address(asset));
        }

        vm.expectRevert(EulerRedemptionBridge.SlippageExceeded.selector);
        bridge.convert(
            aztecInputAsset, emptyAsset, aztecExitAsset, emptyAsset, exitAmount, 0, type(uint64).max, address(0)
        );
    }

    function testWrongInputAsset() public {
        AztecTypes.AztecAsset memory aztecEthAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(aztecEthAsset, emptyAsset, aztecEthAsset, emptyAsset, 0, 0, type(uint64).max, address(0));
    }

    function testWrongOutputAsset() public {
        for (uint256 i = 0; i < 3; i++) {
            AztecTypes.AztecAsset memory aztecInputAsset = ROLLUP_ENCODER.getRealAztecAsset(address(weAssets[i]));

            AztecTypes.AztecAsset memory aztecOutputAsset =
                ROLLUP_ENCODER.getRealAztecAsset(ROLLUP_PROCESSOR.getSupportedAsset(10));

            vm.expectRevert(ErrorLib.InvalidOutputA.selector);
            bridge.convert(aztecInputAsset, emptyAsset, aztecOutputAsset, emptyAsset, 1, 0, 0, address(0));
        }
    }

    function _migratorAmounts(ERC4626Migrator _migrator, uint256 _wethAmount, uint256 _daiAmount, uint256 _usdcAmount)
        internal
    {
        // Mint assets to self, then transfer to the migrator
        deal(address(WETH), address(this), _wethAmount);
        deal(address(DAI), address(this), _daiAmount);
        deal(address(USDC), address(this), _usdcAmount);

        WETH.transfer(address(_migrator), _wethAmount);
        DAI.transfer(address(_migrator), _daiAmount);
        USDC.transfer(address(_migrator), _usdcAmount);
    }
}
