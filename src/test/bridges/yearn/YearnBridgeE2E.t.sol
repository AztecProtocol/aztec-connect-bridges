// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IYearnVault} from "../../../interfaces/yearn/IYearnVault.sol";
import {IYearnRegistry} from "../../../interfaces/yearn/IYearnRegistry.sol";
import {YearnBridge} from "../../../bridges/yearn/YearnBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

contract YearnBridgeE2ETest is BridgeTestBase {
    using SafeERC20 for IERC20;

    struct Balances {
        uint256 underlyingBefore;
        uint256 underlyingMid;
        uint256 underlyingEnd;
        uint256 sharesBefore;
        uint256 sharesMid;
        uint256 sharesEnd;
    }

    IERC20 public constant YVETH = IERC20(0xa258C4606Ca8206D8aA700cE2143D7db854D168c);
    IERC20 public constant OLD_YVETH = IERC20(0xa9fE4601811213c340e850ea305481afF02f5b28);
    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    YearnBridge internal bridge;
    uint256 internal id;

    function setUp() public {
        bridge = new YearnBridge(address(ROLLUP_PROCESSOR));
        bridge.preApproveAll();
        vm.label(address(bridge), "YEARN_BRIDGE");
        vm.deal(address(bridge), 0);

        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 5000000);

        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();
    }

    function testPreApproveOne() public {
        IYearnRegistry _registry = bridge.YEARN_REGISTRY();
        address vault = _registry.latestVault(address(DAI));
        bridge.preApprove(vault);
    }

    function testPreApprove() public {
        IYearnRegistry _registry = bridge.YEARN_REGISTRY();
        uint256 numTokens = _registry.numTokens();
        for (uint256 i; i < numTokens; ++i) {
            address token = _registry.tokens(i);
            address vault = _registry.latestVault(token);
            bridge.preApprove(vault);
        }
    }

    function testPreApproveReverts() public {
        address nonVaultTokenAddress = 0x3cD751E6b0078Be393132286c442345e5DC49699;

        vm.expectRevert();
        bridge.preApprove(nonVaultTokenAddress);
    }

    function testPreApproveWhenAllowanceNotZero(uint256 _currentAllowance) public {
        vm.assume(_currentAllowance > 0);
        // Set allowances to _currentAllowance for all the cTokens and its underlying
        vm.startPrank(address(bridge));
        IYearnRegistry _registry = bridge.YEARN_REGISTRY();
        uint256 numTokens = _registry.numTokens();
        for (uint256 i; i < numTokens; ++i) {
            address _token = _registry.tokens(i);
            address _vault = _registry.latestVault(_token);
            IYearnVault yVault = IYearnVault(_vault);
            uint256 allowance = yVault.allowance(address(this), address(ROLLUP_PROCESSOR));
            if (allowance < _currentAllowance) {
                yVault.approve(address(ROLLUP_PROCESSOR), _currentAllowance - allowance);
            }

            IERC20 underlying = IERC20(yVault.token());
            allowance = underlying.allowance(address(this), address(yVault));
            if (allowance != type(uint256).max) {
                underlying.safeApprove(address(yVault), 0);
                underlying.safeApprove(address(yVault), type(uint256).max);
            }
            allowance = underlying.allowance(address(this), address(ROLLUP_PROCESSOR));
            if (allowance != type(uint256).max) {
                underlying.safeApprove(address(ROLLUP_PROCESSOR), 0);
                underlying.safeApprove(address(ROLLUP_PROCESSOR), type(uint256).max);
            }
        }
        vm.stopPrank();

        // Verify that preApproveAll() doesn't fail
        bridge.preApproveAll();
    }

    function testERC20DepositAndWithdrawal(uint256 _depositAmount, uint256 _redeemAmount) public {
        IYearnRegistry _registry = bridge.YEARN_REGISTRY();
        address vault = _registry.latestVault(address(DAI));
        uint256 availableDepositLimit = IYearnVault(vault).availableDepositLimit();
        if (availableDepositLimit > 0) {
            _depositAndWithdrawERC20(vault, _depositAmount, _redeemAmount);
        }
    }

    function testETHDepositAndWithdrawal(uint256 _depositAmount, uint256 _redeemAmount) public {
        _depositAndWithdrawETH(_depositAmount, _redeemAmount);
    }

    function testFinalise() public {
        vm.prank(address(ROLLUP_PROCESSOR));
        vm.expectRevert(ErrorLib.AsyncDisabled.selector);
        bridge.finalise(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0);
    }

    function _depositAndWithdrawERC20(
        address _vault,
        uint256 _depositAmount,
        uint256 _redeemAmount
    ) internal {
        uint256 availableDepositLimit = IYearnVault(_vault).availableDepositLimit();
        vm.assume(_depositAmount > 1);
        vm.assume(_depositAmount < availableDepositLimit);

        address underlyingToken = IYearnVault(_vault).token();
        _addSupportedIfNotAdded(underlyingToken);
        _addSupportedIfNotAdded(_vault);
        
        deal(underlyingToken, address(ROLLUP_PROCESSOR), _depositAmount);

        AztecTypes.AztecAsset memory depositInputAssetA = getRealAztecAsset(underlyingToken);
        AztecTypes.AztecAsset memory depositOutputAssetA = getRealAztecAsset(address(_vault));

        uint256 inputAssetABefore = IERC20(underlyingToken).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 outputAssetABefore = IERC20(address(_vault)).balanceOf(address(ROLLUP_PROCESSOR)); 

        // Computes the encoded data for the specific bridge interaction
        uint256 bridgeId = encodeBridgeId(id, depositInputAssetA, emptyAsset, depositOutputAssetA, emptyAsset, 0);
        sendDefiRollup(bridgeId, _depositAmount);
        uint256 inputAssetAMid = IERC20(underlyingToken).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 outputAssetAMid = IERC20(address(_vault)).balanceOf(address(ROLLUP_PROCESSOR));
        assertEq(inputAssetAMid, inputAssetABefore - _depositAmount, "erc20 bal don't match after deposit");
        assertGt(outputAssetAMid, outputAssetABefore, "no change in output asset balance after deposit");

        //Exit
        vm.assume(_redeemAmount > 1 && _redeemAmount <= outputAssetAMid);
        uint256 outBridgeId = encodeBridgeId(id, depositOutputAssetA, emptyAsset, depositInputAssetA, emptyAsset, 1);
        sendDefiRollup(outBridgeId, _redeemAmount);
        uint256 inputAssetAAfter = IERC20(underlyingToken).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 outputAssetAAfter = IERC20(address(_vault)).balanceOf(address(ROLLUP_PROCESSOR));
        assertGt(inputAssetAAfter, inputAssetAMid, "erc20 bal don't match after withdrawal");
        assertEq(outputAssetAAfter, outputAssetAMid - _redeemAmount, "no change in output asset balance after withdraw");
    }

    function _depositAndWithdrawETH(
        uint256 _depositAmount,
        uint256 _redeemAmount
    ) internal {
        IYearnRegistry _registry = bridge.YEARN_REGISTRY();
        IYearnVault _vault = IYearnVault(_registry.latestVault(address(bridge.WETH())));
        uint256 availableDepositLimit = _vault.availableDepositLimit();
        vm.assume(_depositAmount > 1);
        vm.assume(_depositAmount < availableDepositLimit);
        vm.deal(address(ROLLUP_PROCESSOR), _depositAmount);

        _addSupportedIfNotAdded(address(_vault));

        AztecTypes.AztecAsset memory depositInputAssetA = getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory depositOutputAssetA = getRealAztecAsset(address(_vault));

        uint256 inputAssetABefore = address(ROLLUP_PROCESSOR).balance;
        uint256 outputAssetABefore = IERC20(address(_vault)).balanceOf(address(ROLLUP_PROCESSOR)); 

        // Computes the encoded data for the specific bridge interaction
        uint256 bridgeId = encodeBridgeId(id, depositInputAssetA, emptyAsset, depositOutputAssetA, emptyAsset, 0);
        sendDefiRollup(bridgeId, _depositAmount);
        uint256 inputAssetAMid = address(ROLLUP_PROCESSOR).balance;
        uint256 outputAssetAMid = IERC20(address(_vault)).balanceOf(address(ROLLUP_PROCESSOR));
        assertEq(inputAssetAMid, inputAssetABefore - _depositAmount, "deposit eth - input asset balance too high");
        assertGt(outputAssetAMid, outputAssetABefore, "deposit eth - output asset balance too low");


        //Exit
        vm.assume(_redeemAmount > 1 && _redeemAmount <= outputAssetAMid);
        uint256 outBridgeId = encodeBridgeId(id, depositOutputAssetA, emptyAsset, depositInputAssetA, emptyAsset, 1);
        sendDefiRollup(outBridgeId, _redeemAmount);
        uint256 inputAssetAAfter = address(ROLLUP_PROCESSOR).balance;
        uint256 outputAssetAAfter = IERC20(address(_vault)).balanceOf(address(ROLLUP_PROCESSOR));
        assertGt(inputAssetAAfter, inputAssetAMid, "withdraw eth - input asset balance too low");
        assertEq(outputAssetAAfter, outputAssetAMid - _redeemAmount, "withdraw eth - output asset balance too high");
    }

    function _addSupportedIfNotAdded(address _asset) internal {
        if (!isSupportedAsset(_asset)) {
            vm.prank(MULTI_SIG);
            ROLLUP_PROCESSOR.setSupportedAsset(_asset, 200000);
        }
    }
}
