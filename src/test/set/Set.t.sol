// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IssuanceBridge} from "./../../bridges/set/IssuanceBridge.sol";
import {IController} from "./../../bridges/set/interfaces/IController.sol";
import {ISetToken} from "./../../bridges/set/interfaces/ISetToken.sol";
import {AztecTypes} from "./../../aztec/AztecTypes.sol";

import "forge-std/Test.sol";

contract SetTest is Test {
    // Aztec
    DefiBridgeProxy internal defiBridgeProxy;
    RollupProcessor internal rollupProcessor;

    // Bridges
    IssuanceBridge internal issuanceBridge;

    // ERC20 tokens
    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 public constant DPI = IERC20(0x1494CA1F11D487c2bBe4543E90080AeBa4BA3C2b);

    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    function setUp() public {
        _aztecPreSetup();

        issuanceBridge = new IssuanceBridge(address(rollupProcessor));

        address[] memory tokens = new address[](2);
        tokens[0] = address(DAI);
        tokens[1] = address(DPI);
        issuanceBridge.approveTokens(tokens);
    }

    function testInvalidCaller() public {
        AztecTypes.AztecAsset memory empty;

        vm.prank(address(124));
        vm.expectRevert(IssuanceBridge.InvalidCaller.selector);
        issuanceBridge.convert(empty, empty, empty, empty, 0, 0, 0, address(0));
    }

    function test0InputValue() public {
        AztecTypes.AztecAsset memory empty;

        vm.prank(address(rollupProcessor));
        vm.expectRevert(IssuanceBridge.ZeroInputValue.selector);
        issuanceBridge.convert(empty, empty, empty, empty, 0, 0, 0, address(0));
    }

    function testSetBridge() public {
        // test if we can prefund rollup with tokens and ETH
        uint256 depositAmountDai = 1e9;
        uint256 depositAmountDpi = 2e9;
        uint256 depositAmountEth = 1 ether;

        _setTokenBalance(address(DAI), address(rollupProcessor), depositAmountDai, 2);
        _setTokenBalance(address(DPI), address(rollupProcessor), depositAmountDpi, 0);
        _setEthBalance(address(rollupProcessor), depositAmountEth);

        uint256 rollupBalanceDai = DAI.balanceOf(address(rollupProcessor));
        uint256 rollupBalanceDpi = DPI.balanceOf(address(rollupProcessor));
        uint256 rollupBalanceEth = address(rollupProcessor).balance;

        assertEq(depositAmountDai, rollupBalanceDai, "DAI balance must match");

        assertEq(depositAmountDpi, rollupBalanceDpi, "DPI balance must match");

        assertEq(depositAmountEth, rollupBalanceEth, "ETH balance must match");
    }

    function testIssueSetForExactToken() public {
        // Pre-fund contract with DAI
        uint256 depositAmountDai = 1e21; // 1000 DAI
        _setTokenBalance(address(DAI), address(rollupProcessor), depositAmountDai, 2);

        // Used for unused input/output assets
        AztecTypes.AztecAsset memory empty;

        // DAI is input
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(DAI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        // DPI is output
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(DPI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        uint256 rollupBalanceBeforeDai = DAI.balanceOf(address(rollupProcessor));
        uint256 rollupBalanceBeforeDpi = DPI.balanceOf(address(rollupProcessor));

        // Call rollup's convert function
        (uint256 outputValueA, , ) = rollupProcessor.convert(
            address(issuanceBridge),
            inputAsset,
            empty,
            outputAsset,
            empty,
            depositAmountDai,
            0,
            0
        );

        uint256 rollupBalanceAfterDai = DAI.balanceOf(address(rollupProcessor));
        uint256 rollupBalanceAfterDpi = DPI.balanceOf(address(rollupProcessor));

        assertEq(depositAmountDai, rollupBalanceBeforeDai, "DAI balance before convert must match");

        assertEq(0, rollupBalanceBeforeDpi, "DPI balance before convert must match");

        assertEq(0, rollupBalanceAfterDai, "DAI balance after convert must match");

        assertEq(outputValueA, rollupBalanceAfterDpi, "DPI balance after convert must match");

        assertGt(rollupBalanceAfterDpi, 0, "DPI balance after must be > 0");
    }

    function testIssueSetForExactEth() public {
        // Pre-fund contract with ETH
        uint256 depositAmountEth = 1e17; // 0.1 ETH
        _setEthBalance(address(rollupProcessor), depositAmountEth);

        // Used for unused input/output assets
        AztecTypes.AztecAsset memory empty;

        // DAI is input
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            assetType: AztecTypes.AztecAssetType.ETH
        });

        // DAI is output
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(DPI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        uint256 rollupBalanceBeforeEth = address(rollupProcessor).balance;
        uint256 rollupBalanceBeforeDpi = DPI.balanceOf(address(rollupProcessor));

        (uint256 outputValueA, , ) = rollupProcessor.convert(
            address(issuanceBridge),
            inputAsset,
            empty,
            outputAsset,
            empty,
            depositAmountEth,
            0,
            0
        );

        uint256 rollupBalanceAfterEth = address(rollupProcessor).balance;
        uint256 rollupBalanceAfterDpi = DPI.balanceOf(address(rollupProcessor));

        assertEq(depositAmountEth, rollupBalanceBeforeEth, "ETH balance before convert must match");

        assertEq(0, rollupBalanceBeforeDpi, "DPI balance before convert must match");

        assertEq(0, rollupBalanceAfterEth, "ETH balance after convert must match");

        assertEq(outputValueA, rollupBalanceAfterDpi, "DPI balance after convert must match");

        assertGt(rollupBalanceAfterDpi, 0, "DPI balance after must be > 0");
    }

    function testRedeemExactSetForToken() public {
        // Pre-fund rollup contract DPI
        uint256 depositAmountDpi = 1e20; // 100 DPI
        _setTokenBalance(address(DPI), address(rollupProcessor), depositAmountDpi, 0);

        // Used for unused input/output assets
        AztecTypes.AztecAsset memory empty;

        // DPI is input
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(DPI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        // DAI is output
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(DAI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        uint256 rollupBalanceBeforeDai = DAI.balanceOf(address(rollupProcessor));
        uint256 rollupBalanceBeforeDpi = DPI.balanceOf(address(rollupProcessor));

        // Call rollup's convert function
        (uint256 outputValueA, , ) = rollupProcessor.convert(
            address(issuanceBridge),
            inputAsset,
            empty,
            outputAsset,
            empty,
            depositAmountDpi,
            0,
            0
        );

        uint256 rollupBalanceAfterDai = DAI.balanceOf(address(rollupProcessor));
        uint256 rollupBalanceAfterDpi = DPI.balanceOf(address(rollupProcessor));

        // Checks before
        assertEq(0, rollupBalanceBeforeDai, "DAI balance before convert must match");

        assertEq(depositAmountDpi, rollupBalanceBeforeDpi, "DPI balance before convert must match");

        // Checks after
        assertEq(outputValueA, rollupBalanceAfterDai, "DAI balance after convert must match");

        assertEq(0, rollupBalanceAfterDpi, "DPI balance after convert must match");

        assertGt(rollupBalanceAfterDai, 0, "DAI balance after must be > 0");
    }

    function testRedeemExactSetForEth() public {
        // prefund rollup with tokens
        uint256 depositAmountDpi = 1e20; // 100 DPI
        _setTokenBalance(address(DPI), address(rollupProcessor), depositAmountDpi, 0);

        // Used for unused input/output assets
        AztecTypes.AztecAsset memory empty;

        // DPI is input
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(DPI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        // ETH is output
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE,
            assetType: AztecTypes.AztecAssetType.ETH
        });

        uint256 rollupBalanceBeforeDpi = DPI.balanceOf(address(rollupProcessor));
        uint256 rollupBalanceBeforeEth = address(rollupProcessor).balance;

        (uint256 outputValueA, , ) = rollupProcessor.convert(
            address(issuanceBridge),
            inputAsset,
            empty,
            outputAsset,
            empty,
            depositAmountDpi,
            0,
            0
        );

        uint256 rollupBalanceAfterDpi = DPI.balanceOf(address(rollupProcessor));
        uint256 rollupBalanceAfterEth = address(rollupProcessor).balance;

        // Checks before
        assertEq(0, rollupBalanceBeforeEth, "ETH balance before convert must match");

        assertEq(depositAmountDpi, rollupBalanceBeforeDpi, "DPI balance before convert must match");

        // Checks after
        assertEq(outputValueA, rollupBalanceAfterEth, "ETH balance after convert must match");

        assertEq(0, rollupBalanceAfterDpi, "DPI balance after convert must match");

        assertGt(rollupBalanceAfterEth, 0, "ETH balance after must be > 0");
    }

    function _setTokenBalance(
        address token,
        address user,
        uint256 balance,
        uint256 slot // May vary depending on token
    ) internal {
        vm.store(token, keccak256(abi.encode(user, slot)), bytes32(uint256(balance)));

        assertEq(IERC20(token).balanceOf(user), balance, "wrong token balance");
    }

    function _setEthBalance(address user, uint256 balance) internal {
        vm.deal(user, balance);

        assertEq(user.balance, balance, "wrong ETH balance");
    }
}
