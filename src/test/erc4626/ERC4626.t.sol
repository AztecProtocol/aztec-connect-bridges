// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {Vm} from "../../../lib/forge-std/src/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";
import {IERC4626} from "./../../interfaces/erc4626/IERC4626.sol";
import {VaultBridge} from "./../../bridges/erc4626/VaultBridge.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";

import "forge-std/Test.sol";
import "forge-std/console.sol";

//Tested at block 14886873 may not work at other blocks
// forge test --fork-block-number 14886873  --match-contract ERC4626 --fork-url https://mainnet.infura.io/v3/9928b52099854248b3a096be07a6b23c
contract ERC4626 is Test {
    DefiBridgeProxy defiBridgeProxy;
    RollupProcessor rollupProcessor;

    VaultBridge vaultbridge;

    IERC20 constant maple = IERC20(0x33349B282065b0284d756F0577FB39c158F935e6);
    IERC20 constant fei = IERC20(0xc7283b66Eb1EB5FB86327f08e1B5816b0720212B);
    IERC4626 constant tribeVault = IERC4626(0x4f93Df7Bc0421C9401fD3099cCE4AfE7678B0c63);

    IERC4626 constant vault = IERC4626(0x4937A209D4cDbD3ecD48857277cfd4dA4D82914c);

    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    function setUp() public {
        _aztecPreSetup();

        vaultbridge = new VaultBridge(address(rollupProcessor));

        rollupProcessor.setBridgeGasLimit(address(vaultbridge), 1000000);
    }

    function testVaultBridge1(uint256 _depositAmount) public {
        uint256 depositAmount = bound(_depositAmount, 5000, type(uint96).max);
        // uint256 depositAmount = 5000;
        deal(address(maple), address(rollupProcessor), depositAmount);

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

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = rollupProcessor.convert(
            address(vaultbridge),
            inputAsset,
            empty,
            outputAsset,
            empty,
            depositAmount,
            1,
            0
        );

        uint256 rollupMapleShares = vault.balanceOf(address(rollupProcessor));
        console.log(rollupMapleShares, "ouput amount");
        assertEq(0, outputValueB);
        assertEq(rollupMapleShares, outputValueA);
        (outputValueA, outputValueB, isAsync) = rollupProcessor.convert(
            address(vaultbridge),
            outputAsset,
            empty,
            inputAsset,
            empty,
            outputValueA,
            2,
            0
        );

        uint256 rollupMapleToken = maple.balanceOf(address(rollupProcessor));
        console.log(rollupMapleToken, "withdraw amount");
        assertEq(outputValueA, rollupMapleToken);
        assertEq(0, outputValueB);
    }

    /*function testVaultBridge2() public {
        uint256 depositAmount = 5;
        deal(address(fei), address(rollupProcessor), depositAmount);
        vaultbridge.approvePair(address(tribeVault), address(fei));

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

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = rollupProcessor.convert(
            address(vaultbridge),
            inputAsset,
            empty,
            outputAsset,
            empty,
            depositAmount,
            1,
            0
        );

        uint256 rollupMapleShares = vault.balanceOf(address(rollupProcessor));
        console.log(rollupMapleShares, "ouput amount");
        assertEq(rollupMapleShares, 4996);
        rollupProcessor.convert(address(vaultbridge), outputAsset, empty, inputAsset, empty, rollupMapleShares, 1, 0);
        uint256 rollupMapleToken = maple.balanceOf(address(rollupProcessor));
        console.log(rollupMapleToken, "withdraw amount");
        assertEq(rollupMapleToken, 4999);
        //assertEq(depositAmount, rollupBeefy, 'Balances must match');
        
    }
    **/
}
