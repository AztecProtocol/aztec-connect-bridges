// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626Bridge} from "../../../bridges/erc4626/ERC4626Bridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {WETHVault} from "./mocks/WETHVault.sol";

contract ERC4626Test is BridgeTestBase {
    address[] private shareAddresses = [
        0x4937A209D4cDbD3ecD48857277cfd4dA4D82914c, // xMPL
        0x815C23eCA83261b6Ec689b60Cc4a58b54BC24D8D, // vTHOR
        0x5DcaAF1F0B32244131FEd00dE9c4598Ae526dAb2 // TTV - Tokemak vault
    ];
    AztecTypes.AztecAsset[] private shares;
    AztecTypes.AztecAsset[] private assets;

    ERC4626Bridge private bridge;
    uint256 private id;
    address private wethVault;

    mapping(address => bool) private fuzzerIgnoreList;

    function setUp() public {
        bridge = new ERC4626Bridge(address(ROLLUP_PROCESSOR));

        vm.label(address(bridge), "ERC4626 Bridge");

        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 180000);

        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        wethVault = address(new WETHVault());
        shareAddresses.push(address(wethVault));

        for (uint256 i = 0; i < shareAddresses.length; ++i) {
            address share = shareAddresses[i];
            address asset = IERC4626(share).asset();

            vm.label(share, IERC20Metadata(share).symbol());
            vm.label(asset, IERC20Metadata(asset).symbol());

            vm.startPrank(MULTI_SIG);
            ROLLUP_PROCESSOR.setSupportedAsset(share, 30000);
            ROLLUP_PROCESSOR.setSupportedAsset(asset, 30000);
            vm.stopPrank();

            shares.push(getRealAztecAsset(share));
            assets.push(getRealAztecAsset(asset));

            // EIP-1087 optimization related mints
            deal(share, address(bridge), 1);
            deal(asset, address(bridge), 1);

            // Set the share address to be ignored by the fuzzer
            fuzzerIgnoreList[share] = true;
        }

        // For the following 2 addresses `testListingNonERC4626Reverts` fails as well just with a different error
        fuzzerIgnoreList[0x7109709ECfa91a80626fF3989D68f67F5b1DD12D] = true; // HEVM
        fuzzerIgnoreList[0x0000000000000000000000000000000000000003] = true; // precompile address
    }

    function testInvalidCaller(address _caller) public {
        vm.assume(_caller != address(ROLLUP_PROCESSOR));
        vm.prank(_caller);
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function testInvalidAuxData(uint64 _auxData) public {
        vm.assume(_auxData > 1);
        vm.expectRevert(ErrorLib.InvalidAuxData.selector);
        vm.prank(address(ROLLUP_PROCESSOR));
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, _auxData, address(0));
    }

    function testListingNonERC4626Reverts(address _vault) public {
        vm.assume(!fuzzerIgnoreList[_vault]);
        vm.expectRevert();
        bridge.listVault(_vault);
    }

    function testConvertRevertsWithoutApprovals() public {
        // I wanted to fuzz the addresses here but there doesn't seem to be a cheat-code catching all reverts
        // irrespective of revert message
        vm.prank(address(ROLLUP_PROCESSOR));
        vm.expectRevert("RDT:M:TRANSFER_FROM");
        bridge.convert(assets[0], emptyAsset, shares[0], emptyAsset, 1 ether, 0, 0, address(0));
    }

    function testFullFlow(uint96 _assetAmount, uint96 _shareAmount) public {
        uint256 assetAmount = bound(_assetAmount, 10, type(uint256).max);

        for (uint256 i = 0; i < shares.length; ++i) {
            deal(assets[i].erc20Address, address(ROLLUP_PROCESSOR), assetAmount);

            uint256 expectedAmount = IERC4626(shares[i].erc20Address).previewDeposit(assetAmount);

            bridge.listVault(shares[i].erc20Address);

            uint256 bridgeCallData = encodeBridgeCallData(id, assets[i], emptyAsset, shares[i], emptyAsset, 0);
            (uint256 outputValueA, uint256 outputValueB, bool isAsync) = sendDefiRollup(bridgeCallData, assetAmount);

            assertEq(outputValueA, expectedAmount, "Received amount of shares differs from the expected one");
            assertEq(outputValueB, 0, "Non-zero outputValueB");
            assertFalse(isAsync, "Bridge is not synchronous");

            uint256 processorShareBalanceBeforeRedeem = IERC20(shares[i].erc20Address).balanceOf(
                address(ROLLUP_PROCESSOR)
            );

            // Immediately redeem the shares
            uint256 redeemAmount = bound(_shareAmount, 1, outputValueA);
            uint256 expectedAssetAmountReturned = IERC4626(shares[i].erc20Address).previewRedeem(redeemAmount);

            bridgeCallData = encodeBridgeCallData(id, shares[i], emptyAsset, assets[i], emptyAsset, 1);
            (outputValueA, outputValueB, isAsync) = sendDefiRollup(bridgeCallData, redeemAmount);

            assertEq(
                IERC20(shares[i].erc20Address).balanceOf(address(ROLLUP_PROCESSOR)) + redeemAmount,
                processorShareBalanceBeforeRedeem,
                "Incorrect RollupProcessor share balance after redeem"
            );
            assertEq(
                outputValueA,
                expectedAssetAmountReturned,
                "Received amount of asset differs from the expected one"
            );
            assertEq(outputValueB, 0, "Non-zero outputValueB");
            assertFalse(isAsync, "Bridge is not synchronous");
        }
    }

    function testEthWrappingAndUnwrapping(uint96 _assetAmount) public {
        uint256 assetAmount = bound(_assetAmount, 10, type(uint256).max);
        IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        bridge.listVault(wethVault);

        AztecTypes.AztecAsset memory shareAsset = getRealAztecAsset(wethVault);
        AztecTypes.AztecAsset memory ethAsset = getRealAztecAsset(address(0));

        // Mint ETH to RollupProcessor
        deal(address(ROLLUP_PROCESSOR), assetAmount);

        uint256 expectedAmount = IERC4626(shareAsset.erc20Address).previewDeposit(assetAmount);

        uint256 bridgeCallData = encodeBridgeCallData(id, ethAsset, emptyAsset, shareAsset, emptyAsset, 0);
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = sendDefiRollup(bridgeCallData, assetAmount);

        assertEq(outputValueA, expectedAmount, "Received amount of shares differs from the expected one");
        assertEq(weth.balanceOf(wethVault), assetAmount, "Unexpected vault WETH balance");
        assertEq(outputValueB, 0, "Non-zero outputValueB");
        assertFalse(isAsync, "Bridge is not synchronous");

        // Immediately redeem the shares
        uint256 redeemAmount = outputValueA;

        bridgeCallData = encodeBridgeCallData(id, shareAsset, emptyAsset, ethAsset, emptyAsset, 1);
        (outputValueA, outputValueB, isAsync) = sendDefiRollup(bridgeCallData, redeemAmount);

        assertApproxEqAbs(outputValueA, assetAmount, 2, "Received amount of asset differs from the expected one");
        assertEq(weth.balanceOf(wethVault), 0, "Non-zero vault WETH balance");
        assertEq(address(ROLLUP_PROCESSOR).balance, assetAmount, "Unexpected RollupProcessor ETH balance");
        assertEq(outputValueB, 0, "Non-zero outputValueB");
        assertFalse(isAsync, "Bridge is not synchronous");
    }

    function testFullFlowWithYield(
        uint96 _assetAmount,
        uint96 _shareAmount,
        uint96 _yield
    ) public {
        uint256 assetAmount = bound(_assetAmount, 10, type(uint256).max);
        IERC20 weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        bridge.listVault(wethVault);

        AztecTypes.AztecAsset memory shareAsset = getRealAztecAsset(wethVault);
        AztecTypes.AztecAsset memory ethAsset = getRealAztecAsset(address(0));

        // Mint ETH to RollupProcessor
        deal(address(ROLLUP_PROCESSOR), assetAmount);

        uint256 expectedAmount = IERC4626(shareAsset.erc20Address).previewDeposit(assetAmount);

        uint256 bridgeCallData = encodeBridgeCallData(id, ethAsset, emptyAsset, shareAsset, emptyAsset, 0);
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = sendDefiRollup(bridgeCallData, assetAmount);

        assertEq(outputValueA, expectedAmount, "Received amount of shares differs from the expected one");
        assertEq(weth.balanceOf(wethVault), assetAmount, "Unexpected vault WETH balance");

        // Mint "yield" to the vault
        uint256 newVaultBalance = bound(_yield, assetAmount, assetAmount + 100 ether);
        deal(address(weth), wethVault, newVaultBalance);

        uint256 processorShareBalanceBeforeRedeem = IERC20(shareAsset.erc20Address).balanceOf(
            address(ROLLUP_PROCESSOR)
        );

        // Immediately redeem the shares
        uint256 redeemAmount = bound(_shareAmount, 1, outputValueA);
        uint256 expectedAssetAmountReturned = IERC4626(shareAsset.erc20Address).previewRedeem(redeemAmount);

        bridgeCallData = encodeBridgeCallData(id, shareAsset, emptyAsset, ethAsset, emptyAsset, 1);
        (outputValueA, outputValueB, isAsync) = sendDefiRollup(bridgeCallData, redeemAmount);

        assertEq(
            IERC20(shareAsset.erc20Address).balanceOf(address(ROLLUP_PROCESSOR)) + redeemAmount,
            processorShareBalanceBeforeRedeem,
            "Incorrect RollupProcessor share balance after redeem"
        );
        assertEq(outputValueA, expectedAssetAmountReturned, "Received amount of asset differs from the expected one");
    }
}
