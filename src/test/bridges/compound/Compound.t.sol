// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ICERC20} from "../../../interfaces/compound/ICERC20.sol";
import {CompoundBridge} from "../../../bridges/compound/CompoundBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

contract CompoundTest is BridgeTestBase {
    // solhint-disable-next-line
    address public constant cETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    address[] public cTokens = [
        0xe65cdB6479BaC1e22340E4E755fAE7E509EcD06c, // cAAve
        0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E, // cBAT
        0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4, // cCOMP
        0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643, // cDAI
        0xFAce851a4921ce59e912d19329929CE6da6EB0c7, // cLINK
        0x95b4eF2869eBD94BEb4eEE400a99824BF5DC325b, // cMKR
        0x4B0181102A0112A2ef11AbEE5563bb4a3176c9d7, // cSUSHI
        0x12392F67bdf24faE0AF363c24aC620a2f67DAd86, // cTUSD
        0x35A18000230DA775CAc24873d00Ff85BccdeD550, // cUNI
        0x39AA39c021dfbaE8faC545936693aC917d5E7563, // cUSDC
        0x041171993284df560249B57358F931D9eB7b925D, // cUSDP
        0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9, // cUSDT
        0xccF4429DB6322D5C611ee964527D42E5d685DD6a, // cWBTC2
        0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946, // cYFI
        0xB3319f5D18Bc0D84dD1b4825Dcde5d5f7266d407 // cZRX
    ];

    CompoundBridge internal compoundBridge;
    uint256 internal id;

    function setUp() public {
        compoundBridge = new CompoundBridge(address(ROLLUP_PROCESSOR));
        vm.label(address(compoundBridge), "COMPOUND_BRIDGE");
        vm.deal(address(compoundBridge), 0);

        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(compoundBridge), 5000000);

        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();
    }

    function testERC20DepositAndWithdrawal(uint88 _depositAmount) public {
        for (uint256 i; i < cTokens.length; ++i) {
            _depositAndWithdrawERC20(cTokens[i], _depositAmount);
        }
    }

    function testInvalidCaller() public {
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        compoundBridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function testInvalidInputAsset() public {
        AztecTypes.AztecAsset memory ethAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0x0000000000000000000000000000000000000000),
            assetType: AztecTypes.AztecAssetType.ETH
        });

        vm.prank(address(ROLLUP_PROCESSOR));
        vm.expectRevert(ErrorLib.InvalidInputA.selector);
        compoundBridge.convert(ethAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 1, address(0));
    }

    function testInvalidOutputAsset() public {
        vm.prank(address(ROLLUP_PROCESSOR));
        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        compoundBridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function testIncorrectAuxData() public {
        vm.prank(address(ROLLUP_PROCESSOR));
        vm.expectRevert(ErrorLib.InvalidAuxData.selector);
        compoundBridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 2, address(0));
    }

    function testFinalise() public {
        vm.prank(address(ROLLUP_PROCESSOR));
        vm.expectRevert(ErrorLib.AsyncDisabled.selector);
        compoundBridge.finalise(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0);
    }

    struct Balances {
        uint256 underlyingBefore;
        uint256 underlyingMid;
        uint256 underlyingEnd;
        uint256 cBefore;
        uint256 cMid;
        uint256 cEnd;
    }

    function testETHDepositAndWithdrawalFixed() public {
        testETHDepositAndWithdrawal(0);
    }

    function testETHDepositAndWithdrawal(uint88 _depositAmount) public {
        _addSupportedIfNotAdded(cETH);

        Balances memory bals;

        (uint256 depositAmount, uint256 mintAmount) = _getDepositAndMintAmounts(cETH, _depositAmount);
        vm.deal(address(ROLLUP_PROCESSOR), depositAmount);

        AztecTypes.AztecAsset memory depositInputAssetA = getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory depositOutputAssetA = getRealAztecAsset(cETH);

        bals.underlyingBefore = address(ROLLUP_PROCESSOR).balance;
        bals.cBefore = IERC20(cETH).balanceOf(address(ROLLUP_PROCESSOR));

        uint256 inBridgeId = encodeBridgeId(id, depositInputAssetA, emptyAsset, depositOutputAssetA, emptyAsset, 0);
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(inBridgeId, getNextNonce(), depositAmount, mintAmount, 0, true, "");
        sendDefiRollup(inBridgeId, depositAmount);

        uint256 redeemAmount = mintAmount;
        uint256 redeemedAmount = _getRedeemedAmount(cETH, mintAmount);
        bals.underlyingMid = address(ROLLUP_PROCESSOR).balance;
        bals.cMid = IERC20(cETH).balanceOf(address(ROLLUP_PROCESSOR));

        uint256 outBridgeId = encodeBridgeId(id, depositOutputAssetA, emptyAsset, depositInputAssetA, emptyAsset, 1);
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(outBridgeId, getNextNonce(), redeemAmount, redeemedAmount, 0, true, "");
        sendDefiRollup(outBridgeId, redeemAmount);

        bals.underlyingEnd = address(ROLLUP_PROCESSOR).balance;
        bals.cEnd = IERC20(cETH).balanceOf(address(ROLLUP_PROCESSOR));

        assertEq(bals.underlyingMid, bals.underlyingBefore - depositAmount, "ether bal dont match after deposit");
        assertEq(bals.underlyingEnd, bals.underlyingMid + redeemedAmount, "ether bal dont match after withdrawal");
        assertEq(bals.cMid, bals.cBefore + mintAmount, "cEther bal dont match after deposit");
        assertEq(bals.cEnd, bals.cMid - redeemAmount, "cEther bal dont match after withdrawal");
    }

    function _depositAndWithdrawERC20(address _cToken, uint256 _depositAmount) private {
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

        uint256 inBridgeId = encodeBridgeId(id, depositInputAssetA, emptyAsset, depositOutputAssetA, emptyAsset, 0);
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(inBridgeId, getNextNonce(), depositAmount, mintAmount, 0, true, "");
        sendDefiRollup(inBridgeId, depositAmount);

        uint256 redeemAmount = IERC20(_cToken).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 redeemedAmount = _getRedeemedAmount(_cToken, redeemAmount);
        bals.underlyingMid = IERC20(underlyingToken).balanceOf(address(ROLLUP_PROCESSOR));
        bals.cMid = IERC20(_cToken).balanceOf(address(ROLLUP_PROCESSOR));

        uint256 outBridgeId = encodeBridgeId(id, depositOutputAssetA, emptyAsset, depositInputAssetA, emptyAsset, 1);
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(outBridgeId, getNextNonce(), redeemAmount, redeemedAmount, 0, true, "");
        sendDefiRollup(outBridgeId, redeemAmount);

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
