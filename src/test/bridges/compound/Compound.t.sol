// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICERC20} from "../../../interfaces/compound/ICERC20.sol";
import {CompoundBridge} from "../../../bridges/compound/CompoundBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

contract CompoundTest is BridgeTestBase {
    using SafeERC20 for IERC20;

    struct Balances {
        uint256 underlyingBefore;
        uint256 underlyingMid;
        uint256 underlyingEnd;
        uint256 cBefore;
        uint256 cMid;
        uint256 cEnd;
    }

    // solhint-disable-next-line
    address public constant cETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    CompoundBridge internal bridge;
    uint256 internal id;
    mapping(address => bool) internal isDeprecated;

    function setUp() public {
        emit log_named_uint("block number", block.number);
        bridge = new CompoundBridge(address(ROLLUP_PROCESSOR));
        bridge.preApproveAll();
        vm.label(address(bridge), "COMPOUND_BRIDGE");
        vm.deal(address(bridge), 0);

        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 5000000);

        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        isDeprecated[0x158079Ee67Fce2f58472A96584A73C7Ab9AC95c1] = true; // cREP - Augur v1
        isDeprecated[0xC11b1268C1A384e55C48c2391d8d480264A3A7F4] = true; // legacy cWBTC token
        isDeprecated[0xF5DCe57282A584D2746FaF1593d3121Fcac444dC] = true; // cSAI
    }

    function testPreApprove() public {
        address[] memory cTokens = bridge.COMPTROLLER().getAllMarkets();
        for (uint256 i; i < cTokens.length; ++i) {
            bridge.preApprove(cTokens[i]);
        }
    }

    function testPreApproveReverts() public {
        address nonCTokenAddress = 0x3cD751E6b0078Be393132286c442345e5DC49699;

        vm.expectRevert(CompoundBridge.MarketNotListed.selector);
        bridge.preApprove(nonCTokenAddress);
    }

    function testPreApproveWhenAllowanceNotZero(uint256 _currentAllowance) public {
        vm.assume(_currentAllowance > 0); // not using bound(...) here because the constraint is not strict
        // Set allowances to _currentAllowance for all the cTokens and its underlying
        address[] memory cTokens = bridge.COMPTROLLER().getAllMarkets();
        vm.startPrank(address(bridge));
        for (uint256 i; i < cTokens.length; ++i) {
            ICERC20 cToken = ICERC20(cTokens[i]);
            uint256 allowance = cToken.allowance(address(this), address(ROLLUP_PROCESSOR));
            if (allowance < _currentAllowance) {
                cToken.approve(address(ROLLUP_PROCESSOR), _currentAllowance - allowance);
            }
            if (address(cToken) != cETH) {
                IERC20 underlying = IERC20(cToken.underlying());
                // Using safeApprove(...) instead of approve(...) here because underlying can be Tether;
                allowance = underlying.allowance(address(this), address(cToken));
                if (allowance != type(uint256).max) {
                    underlying.safeApprove(address(cToken), 0);
                    underlying.safeApprove(address(cToken), type(uint256).max);
                }
                allowance = underlying.allowance(address(this), address(ROLLUP_PROCESSOR));
                if (allowance != type(uint256).max) {
                    underlying.safeApprove(address(ROLLUP_PROCESSOR), 0);
                    underlying.safeApprove(address(ROLLUP_PROCESSOR), type(uint256).max);
                }
            }
        }
        vm.stopPrank();

        // Verify that preApproveAll() doesn't fail
        bridge.preApproveAll();
    }

    function testERC20DepositAndWithdrawal(uint88 _depositAmount, uint88 _redeemAmount) public {
        address[] memory cTokens = bridge.COMPTROLLER().getAllMarkets();
        for (uint256 i; i < cTokens.length; ++i) {
            address cToken = cTokens[i];
            if (!isDeprecated[cToken] && cToken != cETH) {
                _depositAndWithdrawERC20(cToken, _depositAmount, _redeemAmount);
            }
        }
    }

    function testInvalidCaller() public {
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function testInvalidInputAsset() public {
        AztecTypes.AztecAsset memory ethAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0x0000000000000000000000000000000000000000),
            assetType: AztecTypes.AztecAssetType.ETH
        });

        vm.prank(address(ROLLUP_PROCESSOR));
        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        bridge.convert(ethAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 1, address(0));
    }

    function testInvalidOutputAsset() public {
        vm.prank(address(ROLLUP_PROCESSOR));
        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function testIncorrectAuxData() public {
        vm.prank(address(ROLLUP_PROCESSOR));
        vm.expectRevert(ErrorLib.InvalidAuxData.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 2, address(0));
    }

    function testFinalise() public {
        vm.prank(address(ROLLUP_PROCESSOR));
        vm.expectRevert(ErrorLib.AsyncDisabled.selector);
        bridge.finalise(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0);
    }

    function testETHDepositAndWithdrawal(uint256 _depositAmount, uint256 _redeemAmount) public {
        _addSupportedIfNotAdded(cETH);

        Balances memory bals;

        (uint256 depositAmount, uint256 mintAmount) = _getDepositAndMintAmounts(cETH, _depositAmount);
        vm.deal(address(ROLLUP_PROCESSOR), depositAmount);

        AztecTypes.AztecAsset memory depositInputAssetA = getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory depositOutputAssetA = getRealAztecAsset(cETH);

        bals.underlyingBefore = address(ROLLUP_PROCESSOR).balance;
        bals.cBefore = IERC20(cETH).balanceOf(address(ROLLUP_PROCESSOR));

        uint256 inBridgeCallData = encodeBridgeCallData(
            id,
            depositInputAssetA,
            emptyAsset,
            depositOutputAssetA,
            emptyAsset,
            0
        );
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(inBridgeCallData, getNextNonce(), depositAmount, mintAmount, 0, true, "");
        sendDefiRollup(inBridgeCallData, depositAmount);

        uint256 redeemAmount = bound(_redeemAmount, 1, mintAmount);
        uint256 redeemedAmount = _getRedeemedAmount(cETH, redeemAmount);
        bals.underlyingMid = address(ROLLUP_PROCESSOR).balance;
        bals.cMid = IERC20(cETH).balanceOf(address(ROLLUP_PROCESSOR));

        uint256 outBridgeCallData = encodeBridgeCallData(
            id,
            depositOutputAssetA,
            emptyAsset,
            depositInputAssetA,
            emptyAsset,
            1
        );
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(outBridgeCallData, getNextNonce(), redeemAmount, redeemedAmount, 0, true, "");
        sendDefiRollup(outBridgeCallData, redeemAmount);

        bals.underlyingEnd = address(ROLLUP_PROCESSOR).balance;
        bals.cEnd = IERC20(cETH).balanceOf(address(ROLLUP_PROCESSOR));

        assertEq(bals.underlyingMid, bals.underlyingBefore - depositAmount, "ether bal dont match after deposit");
        assertEq(bals.underlyingEnd, bals.underlyingMid + redeemedAmount, "ether bal dont match after withdrawal");
        assertEq(bals.cMid, bals.cBefore + mintAmount, "cEther bal dont match after deposit");
        assertEq(bals.cEnd, bals.cMid - redeemAmount, "cEther bal dont match after withdrawal");
    }

    function _depositAndWithdrawERC20(
        address _cToken,
        uint256 _depositAmount,
        uint256 _redeemAmount
    ) internal {
        address underlyingToken = ICERC20(_cToken).underlying();
        _addSupportedIfNotAdded(underlyingToken);
        _addSupportedIfNotAdded(_cToken);

        Balances memory bals;

        (uint256 depositAmount, uint256 mintAmount) = _getDepositAndMintAmounts(_cToken, _depositAmount);

        deal(underlyingToken, address(ROLLUP_PROCESSOR), depositAmount);

        AztecTypes.AztecAsset memory depositInputAssetA = getRealAztecAsset(underlyingToken);
        AztecTypes.AztecAsset memory depositOutputAssetA = getRealAztecAsset(address(_cToken));

        bals.underlyingBefore = IERC20(underlyingToken).balanceOf(address(ROLLUP_PROCESSOR));
        bals.cBefore = IERC20(_cToken).balanceOf(address(ROLLUP_PROCESSOR));

        uint256 inBridgeCallData = encodeBridgeCallData(
            id,
            depositInputAssetA,
            emptyAsset,
            depositOutputAssetA,
            emptyAsset,
            0
        );
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(inBridgeCallData, getNextNonce(), depositAmount, mintAmount, 0, true, "");
        sendDefiRollup(inBridgeCallData, depositAmount);

        uint256 redeemAmount = bound(_redeemAmount, 1, mintAmount);
        uint256 redeemedAmount = _getRedeemedAmount(_cToken, redeemAmount);
        bals.underlyingMid = IERC20(underlyingToken).balanceOf(address(ROLLUP_PROCESSOR));
        bals.cMid = IERC20(_cToken).balanceOf(address(ROLLUP_PROCESSOR));

        uint256 outBridgeCallData = encodeBridgeCallData(
            id,
            depositOutputAssetA,
            emptyAsset,
            depositInputAssetA,
            emptyAsset,
            1
        );
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(outBridgeCallData, getNextNonce(), redeemAmount, redeemedAmount, 0, true, "");
        sendDefiRollup(outBridgeCallData, redeemAmount);

        bals.underlyingEnd = IERC20(underlyingToken).balanceOf(address(ROLLUP_PROCESSOR));
        bals.cEnd = IERC20(_cToken).balanceOf(address(ROLLUP_PROCESSOR));

        assertEq(bals.underlyingMid, bals.underlyingBefore - depositAmount, "token bal dont match after deposit");
        assertEq(bals.underlyingEnd, bals.underlyingMid + redeemedAmount, "token bal dont match after withdrawal");
        assertEq(bals.cMid, bals.cBefore + mintAmount, "cToken bal dont match after deposit");
        assertEq(bals.cEnd, bals.cMid - redeemAmount, "cToken bal dont match after withdrawal");
    }

    function _getDepositAndMintAmounts(address _cToken, uint256 _depositAmount) internal returns (uint256, uint256) {
        uint256 underlyingDecimals = 18;
        if (_cToken != cETH) {
            address underlyingToken = ICERC20(_cToken).underlying();
            underlyingDecimals = IERC20Metadata(underlyingToken).decimals();
        }

        uint256 exchangeRate = ICERC20(_cToken).exchangeRateCurrent();
        uint256 min = 10**underlyingDecimals / 100;
        uint256 max = 10000 * 10**underlyingDecimals;
        uint256 depositAmount = bound(_depositAmount, min, max);
        uint256 mintAmount = (depositAmount * 1e18) / exchangeRate;

        return (depositAmount, mintAmount);
    }

    function _getRedeemedAmount(address _cToken, uint256 _redeemAmount) internal returns (uint256) {
        uint256 exchangeRate = ICERC20(_cToken).exchangeRateCurrent();
        return (_redeemAmount * exchangeRate) / 1e18;
    }

    function _addSupportedIfNotAdded(address _asset) internal {
        if (!isSupportedAsset(_asset)) {
            vm.prank(MULTI_SIG);
            ROLLUP_PROCESSOR.setSupportedAsset(_asset, 200000);
        }
    }
}
