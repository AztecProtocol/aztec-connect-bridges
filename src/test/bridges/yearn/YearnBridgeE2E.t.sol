// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
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
    IERC20 public constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    uint256 public constant SAFE_MAX = 79228162514264337593543950334;
    address private constant BENEFICIARY = address(11);

    YearnBridge internal bridge;
    uint256 internal depositBridgeId;
    uint256 internal withdrawBridgeId;

    event Transfer(address indexed from, address indexed to, uint256 value);

    function setUp() public {
        bridge = new YearnBridge(address(ROLLUP_PROCESSOR));
        bridge.preApproveAll();
        vm.label(address(bridge), "YEARN_BRIDGE");
        vm.deal(address(bridge), 0);

        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 200000);
        depositBridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 1000000);
        withdrawBridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        // Set subsidy
        uint256 criteria = 0; // Subsidizing only deposit
        uint32 gasPerMinute = 200;
        SUBSIDY.subsidize{value: 1 ether}(address(bridge), criteria, gasPerMinute);
        SUBSIDY.registerBeneficiary(BENEFICIARY);
        ROLLUP_ENCODER.setRollupBeneficiary(BENEFICIARY);
    }

    function testERC20DepositAndWithdrawal(uint256 _depositAmount) public {
        IYearnRegistry _registry = bridge.YEARN_REGISTRY();
        address vault = _registry.latestVault(address(DAI));
        uint256 availableDepositLimit = IYearnVault(vault).availableDepositLimit();
        if (availableDepositLimit > 0) {
            uint256 depositAmount = bound(_depositAmount, 1e17, availableDepositLimit);
            _depositAndWithdrawERC20(vault, depositAmount, false);
        }
    }

    function testERC20DepositAndWithdrawalFundsInStrategy(uint80 _depositAmount) public {
        IYearnRegistry _registry = bridge.YEARN_REGISTRY();
        address vault = _registry.latestVault(address(DAI));
        uint256 availableDepositLimit = IYearnVault(vault).availableDepositLimit();
        if (availableDepositLimit > 0) {
            uint256 depositAmount = bound(_depositAmount, 1e17, availableDepositLimit);
            _depositAndWithdrawERC20(vault, depositAmount, true);
        }
    }

    function testMoreERC20DepositAndWithdrawal() public {
        IYearnRegistry _registry = bridge.YEARN_REGISTRY();
        uint256 numTokens = _registry.numTokens();
        for (uint256 i; i < numTokens;) {
            address token = _registry.tokens(i);
            if (
                token == address(WETH) || token == 0xC011a73ee8576Fb46F5E1c5751cA3B9Fe0af2a6F //SNX, packed slot not supported
            ) {
                unchecked {
                    ++i;
                }
                continue;
            }
            address vault = _registry.latestVault(token);
            uint256 availableDepositLimit = IYearnVault(vault).availableDepositLimit();
            if (availableDepositLimit > 0) {
                uint256 depositAmount = bound(1e6, 1e2, availableDepositLimit);
                emit log_named_address("Testing for: ", address(vault));
                _depositAndWithdrawERC20(vault, depositAmount, false);
            }
            unchecked {
                ++i;
            }
        }
    }

    function testETHDepositAndWithdrawal(uint256 _depositAmount, uint256 _withdrawAmount) public {
        IYearnRegistry _registry = bridge.YEARN_REGISTRY();
        address vault = _registry.latestVault(address(WETH));
        uint256 availableDepositLimit = IYearnVault(vault).availableDepositLimit();
        uint256 depositAmount = bound(_depositAmount, 1e17, availableDepositLimit);
        _depositAndWithdrawETH(vault, depositAmount, _withdrawAmount);
    }

    function testFinalise() public {
        vm.prank(address(ROLLUP_PROCESSOR));
        vm.expectRevert(ErrorLib.AsyncDisabled.selector);
        bridge.finalise(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0);
    }

    function _depositAndWithdrawERC20(address _vault, uint256 _depositAmount, bool _reduceVault) internal {
        address underlyingToken = IYearnVault(_vault).token();

        if (underlyingToken == 0xc5bDdf9843308380375a611c18B50Fb9341f502A) {
            vm.prank(MULTI_SIG);
            ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 2000000);
            depositBridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength();

            vm.prank(MULTI_SIG);
            ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 5000000);
            withdrawBridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength();
        }

        _addSupportedIfNotAdded(underlyingToken);
        _addSupportedIfNotAdded(_vault);

        deal(underlyingToken, address(ROLLUP_PROCESSOR), _depositAmount);

        // Warp time for the subsidy to accrue
        vm.warp(block.timestamp + 1 days);

        AztecTypes.AztecAsset memory depositInputAssetA = ROLLUP_ENCODER.getRealAztecAsset(underlyingToken);
        AztecTypes.AztecAsset memory depositOutputAssetA = ROLLUP_ENCODER.getRealAztecAsset(address(_vault));

        uint256 inputAssetABefore = IERC20(underlyingToken).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 outputAssetABefore = IERC20(address(_vault)).balanceOf(address(ROLLUP_PROCESSOR));
        // Computes the encoded data for the specific bridge interaction
        uint256 bridgeCallData = ROLLUP_ENCODER.defiInteractionL2(
            depositBridgeId, depositInputAssetA, emptyAsset, depositOutputAssetA, emptyAsset, 0, _depositAmount
        );
        vm.expectEmit(true, true, false, false); //Log 1 -> transfer _depositAmount from ROLLUP_PROCESSOR to bridge
        emit Transfer(address(ROLLUP_PROCESSOR), address(bridge), _depositAmount);
        vm.expectEmit(true, true, false, false); //Log 2 -> transfer _receiveAmount from 0 to bridge
        emit Transfer(address(0), address(bridge), _depositAmount);
        vm.expectEmit(true, true, false, false); //Log 3 -> transfer _depositAmount from bridge to vault
        emit Transfer(address(bridge), address(_vault), _depositAmount);
        vm.expectEmit(true, true, false, false); //Log 4 -> transfer _receiveAmount from bridge to rollup
        emit Transfer(address(bridge), address(ROLLUP_PROCESSOR), _depositAmount);

        ROLLUP_ENCODER.registerEventToBeChecked(
            bridgeCallData, ROLLUP_ENCODER.getNextNonce(), _depositAmount, _depositAmount, 0, true, ""
        );
        ROLLUP_ENCODER.processRollup();

        uint256 claimableSubsidyAfterDeposit = SUBSIDY.claimableAmount(BENEFICIARY);
        assertGt(SUBSIDY.claimableAmount(BENEFICIARY), 0, "Claimable was not updated");

        uint256 inputAssetAMid = IERC20(underlyingToken).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 outputAssetAMid = IERC20(address(_vault)).balanceOf(address(ROLLUP_PROCESSOR));
        assertEq(inputAssetAMid, inputAssetABefore - _depositAmount, "Balance missmatch after deposit");
        assertGt(outputAssetAMid, outputAssetABefore, "No change in output asset balance after deposit");

        // Move some funds to strategies to have underlying balance be less than the required. Requiring the vault to unwind a position to repay withdraw
        if (_reduceVault) {
            deal(underlyingToken, address(_vault), _depositAmount / 2);
        }

        uint256 withdrawAmount = outputAssetAMid;

        bridgeCallData = ROLLUP_ENCODER.defiInteractionL2(
            withdrawBridgeId, depositOutputAssetA, emptyAsset, depositInputAssetA, emptyAsset, 1, withdrawAmount
        );

        vm.expectEmit(true, true, false, false); //Log 1 -> transfer _withdrawAmount from Rollup to bridge
        emit Transfer(address(ROLLUP_PROCESSOR), address(bridge), withdrawAmount);
        vm.expectEmit(true, true, false, false); //Log 2 -> transfer _withdrawAmount from bridge to 0 (burn yvTokens)
        emit Transfer(address(bridge), address(0), withdrawAmount);
        vm.expectEmit(true, true, false, false); //Log 3 -> transfer _withdrawAmount from vault to bridge
        emit Transfer(address(_vault), address(bridge), withdrawAmount);
        vm.expectEmit(true, true, false, false); //Log 4 -> transfer _withdrawAmount from bridge to Rollup
        emit Transfer(address(bridge), address(ROLLUP_PROCESSOR), withdrawAmount);

        ROLLUP_ENCODER.registerEventToBeChecked(
            bridgeCallData, ROLLUP_ENCODER.getNextNonce(), withdrawAmount, withdrawAmount, 1, true, ""
        );
        ROLLUP_ENCODER.processRollup();
        uint256 inputAssetAAfter = IERC20(underlyingToken).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 outputAssetAAfter = IERC20(address(_vault)).balanceOf(address(ROLLUP_PROCESSOR));

        assertGt(inputAssetAAfter, inputAssetAMid, "Balance missmatch after withdrawal");
        assertEq(
            outputAssetAAfter, outputAssetAMid - withdrawAmount, "No change in output asset balance after withdraw"
        );

        assertEq(
            SUBSIDY.claimableAmount(BENEFICIARY),
            claimableSubsidyAfterDeposit,
            "Claimable subsidy unexpectadly changed after withdrawal"
        );
    }

    function _depositAndWithdrawETH(address _vault, uint256 _depositAmount, uint256 _withdrawAmount) internal {
        vm.deal(address(ROLLUP_PROCESSOR), _depositAmount);
        _addSupportedIfNotAdded(address(_vault));

        AztecTypes.AztecAsset memory depositInputAssetA = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory depositOutputAssetA = ROLLUP_ENCODER.getRealAztecAsset(address(_vault));

        uint256 inputAssetABefore = address(ROLLUP_PROCESSOR).balance;
        uint256 outputAssetABefore = IERC20(address(_vault)).balanceOf(address(ROLLUP_PROCESSOR));

        ROLLUP_ENCODER.defiInteractionL2(
            depositBridgeId, depositInputAssetA, emptyAsset, depositOutputAssetA, emptyAsset, 0, _depositAmount
        );
        ROLLUP_ENCODER.processRollup();
        uint256 inputAssetAMid = address(ROLLUP_PROCESSOR).balance;
        uint256 outputAssetAMid = IERC20(address(_vault)).balanceOf(address(ROLLUP_PROCESSOR));
        assertEq(inputAssetAMid, inputAssetABefore - _depositAmount, "deposit eth - input asset balance too high");
        assertGt(outputAssetAMid, outputAssetABefore, "deposit eth - output asset balance too low");

        ROLLUP_ENCODER.defiInteractionL2(
            withdrawBridgeId, depositOutputAssetA, emptyAsset, depositInputAssetA, emptyAsset, 1, _withdrawAmount
        );
        vm.assume(_withdrawAmount > 1 && _withdrawAmount <= outputAssetAMid);
        ROLLUP_ENCODER.processRollup();
        uint256 inputAssetAAfter = address(ROLLUP_PROCESSOR).balance;
        uint256 outputAssetAAfter = IERC20(address(_vault)).balanceOf(address(ROLLUP_PROCESSOR));
        assertGt(inputAssetAAfter, inputAssetAMid, "withdraw eth - input asset balance too low");
        assertEq(outputAssetAAfter, outputAssetAMid - _withdrawAmount, "withdraw eth - output asset balance too high");
    }

    function _addSupportedIfNotAdded(address _asset) internal {
        if (!ROLLUP_ENCODER.isSupportedAsset(_asset)) {
            vm.prank(MULTI_SIG);
            ROLLUP_PROCESSOR.setSupportedAsset(_asset, 200000);
        }
    }
}
