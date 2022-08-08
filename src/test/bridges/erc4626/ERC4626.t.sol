// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import {ERC4626Bridge} from "../../../bridges/erc4626/ERC4626Bridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

contract ERC4626Test is BridgeTestBase {
    address public constant xMPL = 0x4937A209D4cDbD3ecD48857277cfd4dA4D82914c;
    address public constant vTHOR = 0x815C23eCA83261b6Ec689b60Cc4a58b54BC24D8D;

    ERC4626Bridge internal bridge;
    uint256 private id;

    AztecTypes.AztecAsset[] private shares;
    AztecTypes.AztecAsset[] private assets;

    function setUp() public {
        bridge = new ERC4626Bridge(address(ROLLUP_PROCESSOR));

        address mpl = IERC4626(xMPL).asset();
        address thor = IERC4626(vTHOR).asset();

        vm.label(address(bridge), "ERC4626 Bridge");
        vm.label(mpl, "MPL");
        vm.label(xMPL, "xMPL");
        vm.label(thor, "THOR");
        vm.label(vTHOR, "vTHOR");

        vm.startPrank(MULTI_SIG);

        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 1000000);

        ROLLUP_PROCESSOR.setSupportedAsset(xMPL, 100000);
        ROLLUP_PROCESSOR.setSupportedAsset(mpl, 100000);
        ROLLUP_PROCESSOR.setSupportedAsset(vTHOR, 100000);
        ROLLUP_PROCESSOR.setSupportedAsset(thor, 100000);
        vm.stopPrank();

        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        shares.push(getRealAztecAsset(xMPL));
        assets.push(getRealAztecAsset(mpl));
        shares.push(getRealAztecAsset(vTHOR));
        assets.push(getRealAztecAsset(thor));
    }

    function testFullFlow(uint96 _assetAmount) public {
        uint256 assetAmount = bound(_assetAmount, 10, type(uint256).max);

        for (uint256 i = 0; i < shares.length; ++i) {
            deal(assets[i].erc20Address, address(bridge), assetAmount);

            uint256 expectedAmount = IERC4626(shares[i].erc20Address).previewDeposit(assetAmount);

            bridge.listVault(shares[i].erc20Address);

            vm.prank(address(ROLLUP_PROCESSOR));
            (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
                assets[i],
                emptyAsset,
                shares[i],
                emptyAsset,
                assetAmount,
                0,
                0, // issuance flow
                address(0)
            );

            assertEq(outputValueA, expectedAmount, "Received amount of shares differs from the expected one");
            assertEq(outputValueB, 0, "Non-zero outputValueB");
            assertFalse(isAsync, "Bridge is not synchronous");

            // Immediately redeem the shares
            uint256 redeemAmount = outputValueA;

            vm.prank(address(ROLLUP_PROCESSOR));
            (outputValueA, outputValueB, isAsync) = bridge.convert(
                shares[i],
                emptyAsset,
                assets[i],
                emptyAsset,
                redeemAmount,
                0,
                1, // redeem flow
                address(0)
            );

            assertApproxEqAbs(outputValueA, assetAmount, 2, "Received amount of asset differs from the expected one");
            assertEq(outputValueB, 0, "Non-zero outputValueB");
            assertFalse(isAsync, "Bridge is not synchronous");
        }
    }
}
