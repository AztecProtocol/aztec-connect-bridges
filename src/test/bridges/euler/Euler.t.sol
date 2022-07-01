// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IEulerEToken} from "../../../interfaces/euler/IEulerEtoken.sol";
import {EulerLendingBridge} from "../../../bridges/euler/EulerLendingBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

contract EulerTest is BridgeTestBase {
    using SafeERC20 for IERC20;

    struct Balances {
        uint256 underlyingBefore;
        uint256 underlyingMid;
        uint256 underlyingEnd;
        uint256 cBefore;
        uint256 cMid;
        uint256 cEnd;
    }
    
    EulerLendingBridge internal bridge;
    uint256 internal id;
    mapping(address => bool) internal isDeprecated;
    
     function setUp() public {
        emit log_named_uint("block number", block.number);
        bridge = new EulerLendingBridge(address(ROLLUP_PROCESSOR));
        bridge.preApproveAll();
        vm.label(address(bridge), "EULER_BRIDGE");
        vm.deal(address(bridge), 0);

        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 5000000);

        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        isDeprecated[0xEb91861f8A4e1C12333F42DCE8fB0Ecdc28dA716] = true; // eUSDC
        isDeprecated[0x05305a615419D8CCE92FE3d5990A3C0C8e814716] = true; // eCOMP
        isDeprecated[0x22729F64490d7A4941d64f47719cDa5c8CA4Ec32] = true; // eDAI
    }
    
    function testPreApprove() public {
        address[] memory underlying;
        for (uint256 i; i < underlying.length; ++i) {
            bridge.preApprove(underlying[i]);
        }
    }
    
        function testPreApproveReverts() public {
        address nonCTokenAddress = 0x761d38e5ddf6ccf6cf7c55759d5210750b5d60f3;  //Dogelon Mars

        vm.expectRevert(EulerLendingBridge.MarketNotListed.selector);
        bridge.preApprove(nonCTokenAddress);
    }
    
        function testPreApproveWhenAllowanceNotZero(uint256 _currentAllowance) public {
        vm.assume(_currentAllowance > 0); // not using bound(...) here because the constraint is not strict
        // Set allowances to _currentAllowance for all underlying and its eTokens
        address[] memory underlying;
        vm.startPrank(address(bridge));
        for (uint256 i; i < underlying.length; ++i) {
            IEulerEToken _underlying = IEulerEToken(underlying[i]);
            uint256 allowance = _underlying.allowance(address(this), address(ROLLUP_PROCESSOR));
            if (allowance < _currentAllowance) {
                _underlying.approve(address(ROLLUP_PROCESSOR), _currentAllowance - allowance);
            }
            
                IERC20 eToken = IERC20(_underlying.underlyingToEToken());
                // Using safeApprove(...) instead of approve(...) here because underlying can be Tether;
                allowance = eToken.allowance(address(this), address(cToken));
                if (allowance != type(uint256).max) {
                    eToken.safeApprove(address(_underlying), 0);
                    eToken.safeApprove(address(_underlying), type(uint256).max);
                }
                allowance = eToken.allowance(address(this), address(ROLLUP_PROCESSOR));
                if (allowance != type(uint256).max) {
                    eToken.safeApprove(address(ROLLUP_PROCESSOR), 0);
                    eToken.safeApprove(address(ROLLUP_PROCESSOR), type(uint256).max);
            }
        }
        
        
        vm.stopPrank();
        
        bridge.preApproveAll();
        
        function testERC20DepositAndWithdrawal(uint88 _depositAmount, uint88 _withdrawAmount) public {
        address[] memory _underlying;
        for (uint256 i; i < _underlying.length; ++i) {
            address underlying = _underlying[i];
                _depositAndWithdrawERC20(underlying, _depositAmount, _redeemAmount);
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
    
        function _depositAndWithdrawERC20(
        address _underlying,
        uint256 _depositAmount,
        uint256 _redeemAmount
    ) internal {
        address ETOKEN = IEulerEToken(_underlying).underlyingToEToken();
        _addSupportedIfNotAdded(ETOKEN);

        Balances memory bals;

        (uint256 depositAmount, uint256 mintAmount) = _getDepositAndMintAmounts(_underlying, _depositAmount);

        deal(_underlying, address(ROLLUP_PROCESSOR), depositAmount);

        AztecTypes.AztecAsset memory depositInputAssetA = getRealAztecAsset(_underlying);
        AztecTypes.AztecAsset memory depositOutputAssetA = getRealAztecAsset(address(ETOKEN));

        bals.underlyingBefore = IERC20(_underlying).balanceOf(address(ROLLUP_PROCESSOR));
        bals.eBefore = IERC20(ETOKEN).balanceOf(address(ROLLUP_PROCESSOR));

        uint256 inBridgeId = encodeBridgeId(id, depositInputAssetA, emptyAsset, depositOutputAssetA, emptyAsset, 0);
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(inBridgeId, getNextNonce(), depositAmount, mintAmount, 0, true, "");
        sendDefiRollup(inBridgeId, depositAmount);

        uint256 redeemAmount = bound(_redeemAmount, 1, mintAmount);
        uint256 redeemedAmount = _getRedeemedAmount(ETOKEN, redeemAmount);
        bals.underlyingMid = IERC20(_underlying).balanceOf(address(ROLLUP_PROCESSOR));
        bals.cMid = IERC20(ETOKEN).balanceOf(address(ROLLUP_PROCESSOR));

        uint256 outBridgeId = encodeBridgeId(id, depositOutputAssetA, emptyAsset, depositInputAssetA, emptyAsset, 1);
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(outBridgeId, getNextNonce(), redeemAmount, redeemedAmount, 0, true, "");
        sendDefiRollup(outBridgeId, redeemAmount);

        bals.underlyingEnd = IERC20(_underlying).balanceOf(address(ROLLUP_PROCESSOR));
        bals.cEnd = IERC20(ETOKEN).balanceOf(address(ROLLUP_PROCESSOR));

        assertEq(bals.underlyingMid, bals.underlyingBefore - depositAmount, "token bal dont match after deposit");
        assertEq(bals.underlyingEnd, bals.underlyingMid + redeemedAmount, "token bal dont match after withdrawal");
        assertEq(bals.cMid, bals.cBefore + mintAmount, "cToken bal dont match after deposit");
        assertEq(bals.cEnd, bals.cMid - redeemAmount, "cToken bal dont match after withdrawal");
    }
    
        function _addSupportedIfNotAdded(address _asset) internal {
        if (!isSupportedAsset(_asset)) {
            vm.prank(MULTI_SIG);
            ROLLUP_PROCESSOR.setSupportedAsset(_asset, 200000);
        }
    }
    
    
    
    }

    
    

    
    
        
        
         
         
    
    
    
    
    
    
    
    

    
