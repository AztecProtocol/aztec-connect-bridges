// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {YearnBridge} from "../../../bridges/yearn/YearnBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {IYearnRegistry} from "../../../interfaces/yearn/IYearnRegistry.sol";
import {IYearnVault} from "../../../interfaces/yearn/IYearnVault.sol";

// @notice The purpose of this test is to directly test convert functionality of the bridge.
contract YearnBridgeUnitTest is Test {
    IERC20 public constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IYearnVault public constant YVETH = IYearnVault(0xa258C4606Ca8206D8aA700cE2143D7db854D168c);
    IYearnVault public constant YVDAI = IYearnVault(0xdA816459F1AB5631232FE5e97a05BBBb94970c95);

    AztecTypes.AztecAsset internal emptyAsset;
    IYearnRegistry internal registry;

    address private rollupProcessor;
    YearnBridge private bridge;

    // @dev This method exists on RollupProcessor.sol. It's defined here in order to be able to receive ETH like a real rollup processor would.
    function receiveEthFromBridge(uint256 _interactionNonce) external payable {}

    function setUp() public {
        // In unit tests we set address of rollupProcessor to the address of this test contract
        rollupProcessor = address(this);

        // Deploy a new example bridge
        bridge = new YearnBridge(rollupProcessor);
        vm.label(address(bridge), "YEARN_BRIDGE");
        vm.deal(address(bridge), 0);
        bridge.preApproveAll();
        registry = bridge.YEARN_REGISTRY();

        // Some more labels
        address yvDAI = registry.latestVault(address(DAI));
        vm.label(address(registry), "YEARN_REGISTRY");
        vm.label(address(DAI), "DAI");
        vm.label(address(WETH), "WETH");
        vm.label(address(yvDAI), "yvDAI");
        vm.label(address(YVETH), "yvETH");
    }

    function testInvalidCaller(address _callerAddress) public {
        vm.assume(_callerAddress != rollupProcessor);
        // Use HEVM cheatcode to call from a different address than is address(this)
        vm.prank(_callerAddress);
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    function testInvalidOutputAsset() public {
        vm.prank(rollupProcessor);
        vm.expectRevert(ErrorLib.InvalidOutputA.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 1, 0, 0, address(0));
    }

    function testInvalidNoValueETH() public {
        AztecTypes.AztecAsset memory depositInputAssetA =
            AztecTypes.AztecAsset({id: 0, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.ETH});
        AztecTypes.AztecAsset memory depositOutputAssetA =
            AztecTypes.AztecAsset({id: 100, erc20Address: address(YVETH), assetType: AztecTypes.AztecAssetType.ERC20});

        vm.prank(rollupProcessor);
        vm.expectRevert();
        bridge.convert(depositInputAssetA, emptyAsset, depositOutputAssetA, emptyAsset, 100, 0, 0, address(0));
    }

    function testIncorrectAuxData() public {
        vm.prank(rollupProcessor);
        vm.expectRevert(ErrorLib.InvalidAuxData.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 1, 0, 2, address(0));
    }

    function testYearnBridgeUnitTestERC20(uint256 _depositAmount, uint256 _withdrawAmount) public {
        address vault = registry.latestVault(address(DAI));
        _depositAmount = bound(_depositAmount, 1e17, IYearnVault(vault).availableDepositLimit());

        deal(address(DAI), address(bridge), _depositAmount);
        uint256 daiBalanceBefore = DAI.balanceOf(address(bridge));

        AztecTypes.AztecAsset memory depositInputAssetA =
            AztecTypes.AztecAsset({id: 1, erc20Address: address(DAI), assetType: AztecTypes.AztecAssetType.ERC20});
        AztecTypes.AztecAsset memory depositOutputAssetA =
            AztecTypes.AztecAsset({id: 1, erc20Address: address(vault), assetType: AztecTypes.AztecAssetType.ERC20});

        // Deposit
        (uint256 outputValueA,,) = bridge.convert(
            depositInputAssetA, emptyAsset, depositOutputAssetA, emptyAsset, _depositAmount, 0, 0, address(0)
        );
        uint256 daiBalanceMid = DAI.balanceOf(address(bridge));
        uint256 shareAmountMid = IERC20(address(vault)).balanceOf(address(bridge));
        assertGt(outputValueA, 0, "Share receive should not be 0");
        assertEq(shareAmountMid, outputValueA, "Invalid share amount");
        assertLt(daiBalanceMid, daiBalanceBefore, "DAI balance after is not less than before");

        // Withdraw
        _withdrawAmount = bound(_withdrawAmount, 1, outputValueA);
        (uint256 outputValueA2,,) = bridge.convert(
            depositOutputAssetA, emptyAsset, depositInputAssetA, emptyAsset, _withdrawAmount, 0, 1, address(0)
        );
        uint256 daiBalanceAfter = DAI.balanceOf(address(bridge));
        uint256 shareAmountAfter = IERC20(address(vault)).balanceOf(address(bridge));
        assertGt(outputValueA2, 0, "DAI receive should not be 0");
        assertLt(shareAmountAfter, shareAmountMid, "Invalid share amount");
        assertGt(daiBalanceAfter, daiBalanceMid, "DAI balance after is not more than before");
    }

    function testYearnBridgeUnitTestETH(uint256 _depositAmount, uint256 _withdrawAmount) public {
        address vault = registry.latestVault(address(WETH));
        _depositAmount = bound(_depositAmount, 1e17, IYearnVault(vault).availableDepositLimit());

        vm.deal(address(rollupProcessor), _depositAmount);
        uint256 ethBalanceBefore = address(rollupProcessor).balance;

        AztecTypes.AztecAsset memory depositInputAssetA =
            AztecTypes.AztecAsset({id: 1, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.ETH});
        AztecTypes.AztecAsset memory depositOutputAssetA =
            AztecTypes.AztecAsset({id: 2, erc20Address: address(vault), assetType: AztecTypes.AztecAssetType.ERC20});

        // Deposit
        (uint256 outputValueA,,) = bridge.convert{value: _depositAmount}(
            depositInputAssetA, emptyAsset, depositOutputAssetA, emptyAsset, _depositAmount, 0, 0, address(0)
        );
        uint256 ethBalanceMid = address(rollupProcessor).balance;
        uint256 shareAmountMid = IERC20(address(vault)).balanceOf(address(bridge));
        assertGt(outputValueA, 0, "Share receive should not be 0");
        assertEq(shareAmountMid, outputValueA, "Invalid share amount");
        assertLt(ethBalanceMid, ethBalanceBefore, "ETH balance after is not less than before");

        // Withdraw
        _withdrawAmount = bound(_withdrawAmount, 1, outputValueA);
        (uint256 outputValueA2,,) = bridge.convert(
            depositOutputAssetA, emptyAsset, depositInputAssetA, emptyAsset, _withdrawAmount, 0, 1, address(0)
        );
        assertGt(outputValueA2, 0, "ETH receive should not be 0");
        assertLt(IERC20(address(vault)).balanceOf(address(bridge)), shareAmountMid, "Invalid share amount");
        assertGt(address(rollupProcessor).balance, ethBalanceMid, "ETH balance after is not more than before");
    }
}
