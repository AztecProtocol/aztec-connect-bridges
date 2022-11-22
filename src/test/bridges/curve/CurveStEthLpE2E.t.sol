// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";

import {ICurvePool} from "../../../interfaces/curve/ICurvePool.sol";
import {ILido} from "../../../interfaces/lido/ILido.sol";
import {IWstETH} from "../../../interfaces/lido/IWstETH.sol";
import {IDefiBridge} from "../../../aztec/interfaces/IDefiBridge.sol";
import {ISubsidy} from "../../../aztec/interfaces/ISubsidy.sol";

import {CurveStEthBridge} from "../../../bridges/curve/CurveStEthBridge.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {Deployer} from "../../../bridges/curve/Deployer.sol";

contract CurveLpE2ETest is BridgeTestBase {
    // solhint-disable-next-line
    IERC20 public constant LP_TOKEN = IERC20(0x06325440D014e39736583c165C2963BA99fAf14E);
    ILido public constant STETH = ILido(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IWstETH public constant WRAPPED_STETH = IWstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);
    ICurvePool public constant CURVE_POOL = ICurvePool(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022);

    address public constant BENEFICIARY = address(0xbeef);

    AztecTypes.AztecAsset private ethAsset;
    AztecTypes.AztecAsset private wstETHAsset;
    AztecTypes.AztecAsset private lpAsset;

    IDefiBridge private bridge;
    uint256 private bridgeAddressId;

    function setUp() public {
        Deployer deployer = new Deployer();

        string[] memory cmds = new string[](2);
        cmds[0] = "vyper";
        cmds[1] = "src/bridges/curve/CurveStEthLpBridge.vy";
        bytes memory code = vm.ffi(cmds);

        bytes memory bytecode = abi.encodePacked(code, abi.encode(address(ROLLUP_PROCESSOR)));
        address bridgeAddress = deployer.deploy(bytecode);

        bridge = IDefiBridge(bridgeAddress);

        vm.deal(address(bridge), 0);
        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 500000);
        bridgeAddressId = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        ethAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        wstETHAsset = ROLLUP_ENCODER.getRealAztecAsset(address(WRAPPED_STETH));

        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedAsset(address(LP_TOKEN), 100000);
        lpAsset = ROLLUP_ENCODER.getRealAztecAsset(address(LP_TOKEN));

        // Prefund to save gas
        deal(address(WRAPPED_STETH), address(ROLLUP_PROCESSOR), WRAPPED_STETH.balanceOf(address(ROLLUP_PROCESSOR)) + 1);
        deal(address(WRAPPED_STETH), address(bridge), 1);
        STETH.submit{value: 10}(address(0));
        STETH.transfer(address(bridge), 10);

        SUBSIDY.registerBeneficiary(BENEFICIARY);
        SUBSIDY.subsidize{value: 1 ether}(bridgeAddress, 0, 180);
        ROLLUP_ENCODER.setRollupBeneficiary(BENEFICIARY);
        vm.warp(block.timestamp + 180 minutes);

        ISubsidy.Subsidy memory sub = SUBSIDY.getSubsidy(bridgeAddress, 0);
        emit log_named_uint("avail", sub.available);
        emit log_named_uint("next ", SUBSIDY.getAccumulatedSubsidyAmount(bridgeAddress, 0));
    }

    function testDepositEth(uint72 _depositAmount) public {
        uint256 claimableBefore = SUBSIDY.claimableAmount(BENEFICIARY);
        testDeposit(true, _depositAmount);
        assertGt(SUBSIDY.claimableAmount(BENEFICIARY), claimableBefore, "No subsidy accumulated");
    }

    function testDepositWstETH(uint72 _depositAmount) public {
        uint256 claimableBefore = SUBSIDY.claimableAmount(BENEFICIARY);
        testDeposit(false, _depositAmount);
        assertGt(SUBSIDY.claimableAmount(BENEFICIARY), claimableBefore, "No subsidy accumulated");
    }

    function testDeposit(bool _isEth, uint72 _depositAmount) public {
        uint256 depositAmount = bound(_depositAmount, 100, type(uint72).max);

        if (_isEth) {
            vm.deal(address(ROLLUP_PROCESSOR), depositAmount + address(ROLLUP_PROCESSOR).balance);
        } else {
            deal(
                address(WRAPPED_STETH),
                address(ROLLUP_PROCESSOR),
                depositAmount + WRAPPED_STETH.balanceOf(address(ROLLUP_PROCESSOR))
            );
        }
        _deposit(_isEth ? ethAsset : wstETHAsset, depositAmount);
    }

    function testMultipleDeposits(bool[5] memory _isEths, uint72[5] memory _depositAmounts) public {
        for (uint256 i = 0; i < 5; i++) {
            vm.warp(block.timestamp + 1 hours);
            testDeposit(_isEths[i], _depositAmounts[i]);
        }
    }

    function testDepositAndWithdrawal(bool _isEth, uint72 _depositAmount, uint72 _withdrawAmount) public {
        testDeposit(_isEth, _depositAmount);

        uint256 lpBalance = LP_TOKEN.balanceOf(address(ROLLUP_PROCESSOR));
        uint256 withdrawValue = bound(_withdrawAmount, 10, lpBalance);

        _withdraw(withdrawValue);
    }

    function _deposit(AztecTypes.AztecAsset memory _inputAsset, uint256 _depositAmount) internal {
        bool isEth = _inputAsset.assetType == AztecTypes.AztecAssetType.ETH;

        uint256 rollupLpBalance = LP_TOKEN.balanceOf(address(ROLLUP_PROCESSOR));
        uint256 rollupInputBalance =
            isEth ? address(ROLLUP_PROCESSOR).balance : WRAPPED_STETH.balanceOf(address(ROLLUP_PROCESSOR));

        ROLLUP_ENCODER.defiInteractionL2(
            bridgeAddressId, _inputAsset, emptyAsset, lpAsset, emptyAsset, 0, _depositAmount
        );

        uint256 claimableBefore = SUBSIDY.claimableAmount(BENEFICIARY);

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        assertGt(SUBSIDY.claimableAmount(BENEFICIARY), claimableBefore, "No subsidy accumulated");

        uint256 rollupLpBalanceAfter = LP_TOKEN.balanceOf(address(ROLLUP_PROCESSOR));
        uint256 rollupInputBalanceAfter =
            isEth ? address(ROLLUP_PROCESSOR).balance : WRAPPED_STETH.balanceOf(address(ROLLUP_PROCESSOR));

        assertEq(rollupLpBalanceAfter, rollupLpBalance + outputValueA, "Did not receive sufficient lptokens");
        assertEq(rollupInputBalanceAfter, rollupInputBalance - _depositAmount, "Did not pay sufficient input");
        assertEq(outputValueB, 0, "Received output B");
        assertFalse(isAsync, "The bridge call is async");
    }

    function _withdraw(uint256 _inputAmount) internal {
        uint256 rollupLpBalance = LP_TOKEN.balanceOf(address(ROLLUP_PROCESSOR));
        uint256 rollupEthBalance = address(ROLLUP_PROCESSOR).balance;
        uint256 rollupWstEThBalance = WRAPPED_STETH.balanceOf(address(ROLLUP_PROCESSOR));

        ROLLUP_ENCODER.defiInteractionL2(bridgeAddressId, lpAsset, emptyAsset, ethAsset, wstETHAsset, 0, _inputAmount);
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        uint256 rollupLpBalanceAfter = LP_TOKEN.balanceOf(address(ROLLUP_PROCESSOR));
        uint256 rollupEthBalanceAfter = address(ROLLUP_PROCESSOR).balance;
        uint256 rollupWstEThBalanceAfter = WRAPPED_STETH.balanceOf(address(ROLLUP_PROCESSOR));

        assertEq(rollupLpBalanceAfter, rollupLpBalance - _inputAmount, "Did not pass sufficient lptokens");
        assertEq(rollupEthBalanceAfter, outputValueA + rollupEthBalance, "Did not receive sufficient eth");
        assertEq(rollupWstEThBalanceAfter, outputValueB + rollupWstEThBalance, "Did not receive sufficient wsteth");
        assertFalse(isAsync, "The bridge call is async");
    }
}
