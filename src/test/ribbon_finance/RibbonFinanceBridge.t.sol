// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {Vm} from "../../../lib/forge-std/src/Vm.sol";

import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RibbonFinanceBridgeContract} from "./../../bridges/ribbon_finance/RibbonFinanceBridge.sol";

import {AztecTypes} from "./../../aztec/AztecTypes.sol";


import "../../../lib/ds-test/src/test.sol";


contract RibbonFinanceBridgeTest is DSTest {

    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    address public immutable WETH = 0xc02aaa39b223fe8d0a0e5c4f27ead9083c756cc2;

    DefiBridgeProxy defiBridgeProxy;
    RollupProcessor rollupProcessor;

    RibbonFinanceBridgeContract ribbonFinanceBridge;
    AztecTypes.AztecAsset emptyAsset;

    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    function setUp() public {
        _aztecPreSetup();

        ribbonFinanceBridge = new RibbonFinanceBridgeContract(
            address(rollupProcessor)
        );

        rollupProcessor.setBridgeGasLimit(address(ribbonFinanceBridge), 100000);
    }

    function testDepositEthThetaV2() public {
        uint256 depositAmount = 10000;
        _setEthBalance(address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1, // TODO: What should this actually be?
            assetType: AztecTypes.AztecAssetType.ETH,
            erc20Address: WETH
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            assetType: AztecTypes.AztecAssetType.VIRTUAL,
            erc20Address: address(0)
        });

        (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        ) = rollupProcessor.convert(
            address(ribbonFinanceBridge),
            inputAsset,
            emptyAsset,
            outputAsset,
            emptyAsset,
            depositAmount,
            1,
            0
        );       
    }

    // function testWithdrawalEthThetaV2() public {
    // }

    // function testDepositWBTCThetaV2() {
    // }

    // function testDepositEthCallThetaV1() {
    // }

    // function testDepositWBTCCallThetaV1() {
    // }

    // function testDepositEthPutThetaV1() {
    // }

    // function testDepositEthPutyvUSDCV1() {
    // }

    function _setEthBalance(
        address user,
        uint256 balance
    ) internal {

        vm.deal(user, balance);

        assertEq(user.balance, balance, "wrong ETH balance");
    }    
}
