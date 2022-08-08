// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IERC4626} from "../../../interfaces/erc4626/IERC4626.sol";
import {ERC4626Bridge} from "../../../bridges/erc4626/ERC4626Bridge.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

import {Test} from "forge-std/Test.sol";

contract ERC4626 is Test {
    address private rollupProcessor;
    ERC4626Bridge private bridge;
    IERC20 public constant MAPLE = IERC20(0x33349B282065b0284d756F0577FB39c158F935e6);

    IERC20 public constant THOR = IERC20(0xa5f2211B9b8170F694421f2046281775E8468044);
    //xMPL Maple Vault
    IERC4626 public constant VAULT = IERC4626(0x4937A209D4cDbD3ecD48857277cfd4dA4D82914c);

    // https://etherscan.io/address/0x815C23eCA83261b6Ec689b60Cc4a58b54BC24D8D#readContract
    IERC4626 public constant VAULT2 = IERC4626(0x815C23eCA83261b6Ec689b60Cc4a58b54BC24D8D);

    function setUp() public {
        rollupProcessor = address(this);

        bridge = new ERC4626Bridge(rollupProcessor);
        vm.deal(address(bridge), 0);
        vm.label(address(bridge), "ERC4626 Bridge");
    }

    function testxMPL(uint256 _depositAmount) public {
        uint256 depositAmount = bound(_depositAmount, 5000, type(uint96).max);

        deal(address(MAPLE), address(bridge), depositAmount);

        bridge.listVault(address(VAULT));

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(MAPLE),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(VAULT),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
            inputAsset,
            empty,
            outputAsset,
            empty,
            depositAmount,
            0,
            0,
            address(0)
        );

        uint256 rollupMAPLEShares = VAULT.balanceOf(address(bridge));

        assertEq(0, outputValueB);
        assertEq(rollupMAPLEShares, outputValueA);
        (outputValueA, outputValueB, isAsync) = bridge.convert(
            outputAsset,
            empty,
            inputAsset,
            empty,
            outputValueA,
            0,
            1,
            address(0)
        );

        uint256 rollupMAPLEToken = MAPLE.balanceOf(address(bridge));

        assertEq(outputValueA, rollupMAPLEToken);
        assertEq(0, outputValueB);
    }

    function testTimelessFi(uint256 _depositAmount) public {
        uint256 depositAmount = bound(_depositAmount, 5000, type(uint96).max);

        deal(address(THOR), address(bridge), depositAmount);

        bridge.listVault(address(VAULT2));

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(THOR),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(VAULT2),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
            inputAsset,
            empty,
            outputAsset,
            empty,
            depositAmount,
            0,
            0,
            address(0)
        );

        uint256 rollupMAPLEShares = VAULT2.balanceOf(address(bridge));

        assertEq(0, outputValueB);
        assertEq(rollupMAPLEShares, outputValueA);
        (outputValueA, outputValueB, isAsync) = bridge.convert(
            outputAsset,
            empty,
            inputAsset,
            empty,
            outputValueA,
            0,
            1,
            address(0)
        );

        uint256 rollupThorToken = THOR.balanceOf(address(bridge));

        assertEq(outputValueA, rollupThorToken);
        assertEq(0, outputValueB);
    }
}
