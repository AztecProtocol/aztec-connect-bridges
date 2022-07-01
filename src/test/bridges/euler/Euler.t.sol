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
        address[] memory underlying = bridge.markets().underlyingToEToken();
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
        address[] memory underlying = bridge.markets().underlyingToEToken();
        vm.startPrank(address(bridge));
        for (uint256 i; i < underlying.length; ++i) {
            IEulerEToken _underlying = IEulerEToken(underlying[i]);
            uint256 allowance = _underlying.allowance(address(this), address(ROLLUP_PROCESSOR));
            if (allowance < _currentAllowance) {
                _underlying.approve(address(ROLLUP_PROCESSOR), _currentAllowance - allowance);
            }
            
                IERC20 etoken = IERC20(_underlying.underlyingToEToken());
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
    
    
    
    
    
    
    
    

    
