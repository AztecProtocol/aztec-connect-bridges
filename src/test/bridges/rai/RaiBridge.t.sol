// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";

import {DefiBridgeProxy} from "../../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "../../../aztec/RollupProcessor.sol";
import {AggregatorV3Interface} from "../../../bridges/rai/interfaces/AggregatorV3Interface.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RaiBridge} from "../../../bridges/rai/RaiBridge.sol";
import {ISafeEngine} from "../../../bridges/rai/interfaces/ISafeEngine.sol";

import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

contract RaiBridgeTest is Test {
    AggregatorV3Interface private constant PRICE_FEED =
        AggregatorV3Interface(0x4ad7B025127e89263242aB68F0f9c4E5C033B489);

    IERC20 private constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 private constant RAI = IERC20(0x03ab458634910AaD20eF5f1C8ee96F1D6ac54919);

    DefiBridgeProxy private defiBridgeProxy;
    RollupProcessor private rollupProcessor;

    RaiBridge private raiBridge;
    uint256 private totalDepositAmount;

    uint256 private interactionNonce = 1;

    function setUp() public {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));

        raiBridge = new RaiBridge(address(rollupProcessor), "Rai-Safe-1", "RS1");

        totalDepositAmount = 0;

        uint256 initialCollateralRatio = 20000;

        _initialize(10e18, initialCollateralRatio);
    }

    function testWethCollateralDeposit() public {
        uint256 depositAmount = 1e18;
        uint256 rollUpRai = _addCollateralWeth(depositAmount);

        _assertCollateralRatio(rollUpRai);
    }

    function testWethCollateralWithdraw() public {
        uint256 raiAmount = 689e18;
        // test that the wethAmount matches what is supposed to be get by the actual collateral ratio
        ISafeEngine.SAFE memory safe = ISafeEngine(raiBridge.SAFE_ENGINE()).safes(
            0x4554482d41000000000000000000000000000000000000000000000000000000,
            raiBridge.SAFE_HANDLER()
        );

        uint256 expectedWethAmount = (safe.lockedCollateral * raiAmount) / safe.generatedDebt;

        uint256 wethAmount = _removeCollateralWeth(raiAmount);

        assertEq(expectedWethAmount, wethAmount, "Expected weth withdraw dont match actual");
    }

    function testWethCollateralWithdrawAll() public {
        uint256 totalWeth = totalDepositAmount;
        uint256 totalRai = RAI.balanceOf(address(rollupProcessor));

        assertGt(totalRai, 0, "No rai to withdraw");

        _removeCollateralWeth(totalRai);

        uint256 wethBal = WETH.balanceOf(address(rollupProcessor));
        assertEq(totalDepositAmount, 0);
        assertEq(wethBal, totalWeth, "Total withdrawAll failed");
    }

    function testEthCollateralDeposit() public {
        uint256 depositAmount = 5e18;
        uint256 rollupRai = _addCollateralEth(depositAmount);

        _assertCollateralRatio(rollupRai);
    }

    function testEthCollateralWithdraw() public {
        uint256 raiAmount = 1000e18;
        // test that the ethAmount matches what is supposed to be get by the actual collateral ratio
        ISafeEngine.SAFE memory safe = ISafeEngine(raiBridge.SAFE_ENGINE()).safes(
            0x4554482d41000000000000000000000000000000000000000000000000000000,
            raiBridge.SAFE_HANDLER()
        );

        uint256 expectedEthAmount = (safe.lockedCollateral * raiAmount) / safe.generatedDebt;

        uint256 ethAmount = _removeCollateralEth(raiAmount);

        assertEq(expectedEthAmount, ethAmount, "Expected eth withdraw dont match actual");
    }

    function _addCollateralWeth(uint256 _depositAmount) internal returns (uint256 rollUpRai) {
        deal(address(WETH), address(rollupProcessor), _depositAmount);

        totalDepositAmount += _depositAmount;

        uint256 initialRollUpRai = RAI.balanceOf(address(rollupProcessor));
        uint256 initialBridgeTokens = raiBridge.balanceOf(address(rollupProcessor));

        (uint256 outputValueA, ) = _addWethConvert(_depositAmount, 0);

        rollUpRai = RAI.balanceOf(address(rollupProcessor));

        assertEq(outputValueA + initialRollUpRai, rollUpRai, "Rai balance dont match");

        // also assert that the rollupProcessor gets equal number of RaiBridge ERC20 tokens
        uint256 bridgeTokens = raiBridge.balanceOf(address(rollupProcessor));
        assertEq(
            rollUpRai - initialRollUpRai,
            bridgeTokens - initialBridgeTokens,
            "bridgeTokens balance dont equal rai balance"
        );
    }

    function _removeCollateralWeth(uint256 _raiAmount) internal returns (uint256 outputValue) {
        AztecTypes.AztecAsset memory empty;

        uint256 initialBalance = WETH.balanceOf(address(rollupProcessor));
        uint256 initialSupply = raiBridge.totalSupply();

        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(RAI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory inputAssetB = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(raiBridge),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(WETH),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (outputValue, , ) = rollupProcessor.convert(
            address(raiBridge),
            inputAssetA,
            inputAssetB,
            outputAsset,
            empty,
            _raiAmount,
            interactionNonce,
            0
        );

        interactionNonce += 1;

        uint256 currSupply = raiBridge.totalSupply();

        // assert bridgeTokens are transferred and burnt
        assertEq(currSupply, initialSupply - _raiAmount, "bridgeTokens not burnt");

        uint256 newBalance = WETH.balanceOf(address(rollupProcessor));

        assertGt(outputValue, 0, "output wEth is zero");
        assertEq(newBalance - initialBalance, outputValue, "Weth balance dont match");

        totalDepositAmount -= outputValue;
    }

    function _addCollateralEth(uint256 _depositAmount) internal returns (uint256 rollUpRai) {
        rollupProcessor.receiveEthFromBridge{value: _depositAmount}(interactionNonce);

        totalDepositAmount += _depositAmount;

        uint256 initialRollUpRai = RAI.balanceOf(address(rollupProcessor));

        AztecTypes.AztecAsset memory empty;

        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.ETH
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(RAI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetB = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(raiBridge),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (uint256 outputValueA, , ) = rollupProcessor.convert(
            address(raiBridge),
            inputAsset,
            empty,
            outputAssetA,
            outputAssetB,
            _depositAmount,
            interactionNonce,
            0
        );

        rollUpRai = RAI.balanceOf(address(rollupProcessor));

        interactionNonce += 1;

        assertGt(outputValueA, 0);

        assertEq(outputValueA + initialRollUpRai, rollUpRai, "Rai balance dont match");
    }

    function _removeCollateralEth(uint256 _raiAmount) internal returns (uint256 outputValue) {
        AztecTypes.AztecAsset memory empty;

        uint256 initialEthBalance = address(rollupProcessor).balance;
        uint256 initialSupply = raiBridge.totalSupply();

        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(RAI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory inputAssetB = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(raiBridge),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.ETH
        });

        (outputValue, , ) = rollupProcessor.convert(
            address(raiBridge),
            inputAssetA,
            inputAssetB,
            outputAsset,
            empty,
            _raiAmount,
            interactionNonce,
            0
        );

        uint256 currSupply = raiBridge.totalSupply();

        // assert bridgeTokens are transferred and burnt
        assertEq(currSupply, initialSupply - _raiAmount, "bridgeTokens not burnt");

        uint256 newEthBalance = address(rollupProcessor).balance;

        assertGt(outputValue, 0, "output eth is zero");
        assertEq(newEthBalance - initialEthBalance, outputValue, "eth balance dont match");

        totalDepositAmount -= outputValue;
    }

    function _initialize(uint256 _depositAmount, uint256 _collateralRatio) internal returns (uint256 rollUpRai) {
        deal(address(WETH), address(rollupProcessor), _depositAmount);

        totalDepositAmount += _depositAmount;

        rollUpRai = RAI.balanceOf(address(rollupProcessor));

        assertEq(rollUpRai, 0, "initial rollup balance not zero");

        (uint256 outputValueA, ) = _addWethConvert(_depositAmount, _collateralRatio);

        rollUpRai = RAI.balanceOf(address(rollupProcessor));

        uint256 bridgeTokensBalance = raiBridge.balanceOf(address(rollupProcessor));

        assertGt(outputValueA, 0);

        assertEq(outputValueA, rollUpRai, "Rai balance dont match");

        assertEq(bridgeTokensBalance, rollUpRai, "Rai balance dont match bridgeTokens balance");
    }

    function _addWethConvert(uint256 _depositAmount, uint256 _collateralRatio)
        internal
        returns (uint256 outputValueA, uint256 outputValueB)
    {
        AztecTypes.AztecAsset memory empty;

        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(WETH),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(RAI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetB = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(raiBridge),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (outputValueA, outputValueB, ) = rollupProcessor.convert(
            address(raiBridge),
            inputAsset,
            empty,
            outputAssetA,
            outputAssetB,
            _depositAmount,
            interactionNonce,
            _collateralRatio
        );

        interactionNonce += 1;
    }

    function _assertCollateralRatio(uint256 _rollUpRai) internal {
        // test the collateral ratio
        (, int256 x, , , ) = PRICE_FEED.latestRoundData();
        uint256 raiToEth = uint256(x);
        uint256 actualCollateralRatio = (totalDepositAmount * 1e22) / raiToEth / _rollUpRai;
        (uint256 expectedCollateralRatio, , ) = raiBridge.getSafeData();
        assertEq(actualCollateralRatio, expectedCollateralRatio, "Collateral ratio not equal expected");
    }
}
