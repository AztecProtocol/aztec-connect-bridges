// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IERC4626} from "../../../interfaces/erc4626/IERC4626.sol";
import {VaultBridge} from "../../../bridges/erc4626/VaultBridge.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

import {Test} from "forge-std/Test.sol";

import "forge-std/console.sol";

//Tested at block 14886873 may not work at other blocks
// forge test --fork-block-number 14886873  --match-contract ERC4626 --fork-url https://mainnet.infura.io/v3/9928b52099854248b3a096be07a6b23c
contract ERC4626 is Test {
    address private rollupProcessor;
    VaultBridge vaultbridge;
    IERC20 constant maple = IERC20(0x33349B282065b0284d756F0577FB39c158F935e6);
    IERC20 constant fei = IERC20(0xc7283b66Eb1EB5FB86327f08e1B5816b0720212B);
    IERC4626 constant tribeVault = IERC4626(0x4f93Df7Bc0421C9401fD3099cCE4AfE7678B0c63);

    IERC4626 constant vault = IERC4626(0x4937A209D4cDbD3ecD48857277cfd4dA4D82914c);

    function _setUp() internal {
        rollupProcessor = address(this);

        vaultbridge = new VaultBridge(rollupProcessor);
        vm.deal(address(vaultbridge), 0);
        vm.label(address(vaultbridge), "ERC4626 Bridge");
    }

    function testVaultBridge1(uint256 _depositAmount) public {
        _setUp();
        uint256 depositAmount = bound(_depositAmount, 5000, type(uint96).max);
        // uint256 depositAmount = 5000;
        deal(address(maple), address(vaultbridge), depositAmount);

        vaultbridge.approvePair(address(vault), address(maple));

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(maple),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(vault),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = vaultbridge.convert(
            inputAsset,
            empty,
            outputAsset,
            empty,
            depositAmount,
            0, // _interactionNonce
            0, // _auxData - not used in the example bridge
            address(0) // _rollupBeneficiary - not relevant in this context
        );

        uint256 rollupMapleShares = vault.balanceOf(address(vaultbridge));

        assertEq(0, outputValueB);
        assertEq(rollupMapleShares, outputValueA);
        (outputValueA, outputValueB, isAsync) = vaultbridge.convert(
            outputAsset,
            empty,
            inputAsset,
            empty,
            outputValueA,
            0, // _interactionNonce
            0, // _auxData - not used in the example bridge
            address(0) // _rollupBeneficiary - not relevant in this context
        );

        uint256 rollupMapleToken = maple.balanceOf(address(vaultbridge));

        assertEq(outputValueA, rollupMapleToken);
        assertEq(0, outputValueB);
    }
}
