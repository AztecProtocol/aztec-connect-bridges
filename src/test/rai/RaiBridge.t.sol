// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import "../../../lib/ds-test/src/test.sol";
import {Vm} from "../../../lib/forge-std/src/Vm.sol";

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";
import {AggregatorV3Interface} from "./../../bridges/rai/interfaces/AggregatorV3Interface.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RaiBridge} from "./../../bridges/rai/RaiBridge.sol";
import {ISafeEngine} from "./../../bridges/rai/interfaces/ISafeEngine.sol";

import {AztecTypes} from "./../../aztec/AztecTypes.sol";

contract RaiBridgeTest is DSTest {
    using SafeMath for uint256;

    uint256 private interactionNonce = 1;

    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    DefiBridgeProxy defiBridgeProxy;
    RollupProcessor rollupProcessor;

    RaiBridge raiBridge;

    AggregatorV3Interface internal priceFeed = AggregatorV3Interface(0x4ad7B025127e89263242aB68F0f9c4E5C033B489);

    IERC20 constant weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant rai = IERC20(0x03ab458634910AaD20eF5f1C8ee96F1D6ac54919);

    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    uint256 totalDepositAmount;

    function setUp() public {
        _aztecPreSetup();

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

        uint256 expectedWethAmount = safe.lockedCollateral.mul(raiAmount).div(safe.generatedDebt);

        uint256 wethAmount = _removeCollateralWeth(raiAmount);

        require(expectedWethAmount == wethAmount, "Expected weth withdraw dont match actual");
    }

    function testWethCollateralWithdrawAll() public {
        uint256 totalWeth = totalDepositAmount;
        uint256 totalRai = rai.balanceOf(address(rollupProcessor));

        require(totalRai > 0, "No rai to withdraw");

        _removeCollateralWeth(totalRai);

        uint256 wethBal = weth.balanceOf(address(rollupProcessor));
        require(totalDepositAmount == 0);
        require(wethBal == totalWeth, "Total withdrawAll failed");
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

        uint256 expectedEthAmount = safe.lockedCollateral.mul(raiAmount).div(safe.generatedDebt);

        uint256 ethAmount = _removeCollateralEth(raiAmount);

        require(expectedEthAmount == ethAmount, "Expected eth withdraw dont match actual");
    }

    // percentageThreshold is in BPS (divide by 10000)
    function assertApprox(
        uint256 actual,
        uint256 expected,
        uint256 percentageThreshold,
        string memory errorMsg
    ) internal {
        uint256 diff;
        if (actual > expected) {
            diff = actual - expected;
        } else {
            diff = expected - actual;
        }

        require(diff < (actual.mul(percentageThreshold).div(10000)), errorMsg);
    }

    function assertNotEq(address a, address b) internal {
        if (a == b) {
            emit log("Error: a != b not satisfied [address]");
            emit log_named_address("  Expected", b);
            emit log_named_address("    Actual", a);
            fail();
        }
    }

    function _setTokenBalance(
        address token,
        address user,
        uint256 balance
    ) internal {
        uint256 slot = 3; // May vary depending on token

        vm.store(token, keccak256(abi.encode(user, slot)), bytes32(uint256(balance)));

        assertEq(IERC20(token).balanceOf(user), balance, "wrong balance");
    }

    function _addCollateralWeth(uint256 depositAmount) internal returns (uint256 rollUpRai) {
        _setTokenBalance(address(weth), address(rollupProcessor), depositAmount);

        totalDepositAmount += depositAmount;

        uint256 initialRollUpRai = rai.balanceOf(address(rollupProcessor));
        uint256 initialBridgeTokens = raiBridge.balanceOf(address(rollupProcessor));

        AztecTypes.AztecAsset memory empty;

        (uint256 outputValueA, uint256 outputValueB) = _addWethConvert(depositAmount, 0);

        rollUpRai = rai.balanceOf(address(rollupProcessor));

        require(outputValueA + initialRollUpRai == rollUpRai, "Rai balance dont match");

        // also assert that the rollupProcessor gets equal number of RaiBridge ERC20 tokens
        uint256 bridgeTokens = raiBridge.balanceOf(address(rollupProcessor));
        require(
            rollUpRai - initialRollUpRai == bridgeTokens - initialBridgeTokens,
            "bridgeTokens balance dont equal rai balance"
        );
    }

    function _removeCollateralWeth(uint256 raiAmount) internal returns (uint256 outputValue) {
        AztecTypes.AztecAsset memory empty;

        uint256 initialBalance = weth.balanceOf(address(rollupProcessor));
        uint256 initialSupply = raiBridge.totalSupply();

        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(rai),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory inputAssetB = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(raiBridge),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(weth),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (outputValue, , ) = rollupProcessor.convert(
            address(raiBridge),
            inputAssetA,
            inputAssetB,
            outputAsset,
            empty,
            raiAmount,
            interactionNonce,
            0
        );

        interactionNonce += 1;

        uint256 currSupply = raiBridge.totalSupply();

        // assert bridgeTokens are transferred and burnt
        require(currSupply == initialSupply - raiAmount, "bridgeTokens not burnt");

        uint256 newBalance = weth.balanceOf(address(rollupProcessor));

        require(outputValue > 0, "output wEth is zero");
        require(newBalance - initialBalance == outputValue, "Weth balance dont match");

        totalDepositAmount -= outputValue;
    }

    function _addCollateralEth(uint256 depositAmount) internal returns (uint256 rollUpRai) {
        rollupProcessor.receiveEthFromBridge{value: depositAmount}(interactionNonce);

        totalDepositAmount += depositAmount;

        uint256 initialRollUpRai = rai.balanceOf(address(rollupProcessor));

        AztecTypes.AztecAsset memory empty;

        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.ETH
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(rai),
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
            depositAmount,
            interactionNonce,
            0
        );

        rollUpRai = rai.balanceOf(address(rollupProcessor));

        interactionNonce += 1;

        require(outputValueA > 0);

        require(outputValueA + initialRollUpRai == rollUpRai, "Rai balance dont match");
    }

    function _removeCollateralEth(uint256 raiAmount) internal returns (uint256 outputValue) {
        AztecTypes.AztecAsset memory empty;

        uint256 initialEthBalance = address(rollupProcessor).balance;
        uint256 initialSupply = raiBridge.totalSupply();

        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(rai),
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
            raiAmount,
            interactionNonce,
            0
        );

        uint256 currSupply = raiBridge.totalSupply();

        // assert bridgeTokens are transferred and burnt
        require(currSupply == initialSupply - raiAmount, "bridgeTokens not burnt");

        uint256 newEthBalance = address(rollupProcessor).balance;

        require(outputValue > 0, "output eth is zero");
        require(newEthBalance - initialEthBalance == outputValue, "eth balance dont match");

        totalDepositAmount -= outputValue;
    }

    function _initialize(uint256 depositAmount, uint256 collateralRatio) internal returns (uint256 rollUpRai) {
        _setTokenBalance(address(weth), address(rollupProcessor), depositAmount);

        totalDepositAmount += depositAmount;

        rollUpRai = rai.balanceOf(address(rollupProcessor));

        require(rollUpRai == 0, "initial rollup balance not zero");

        (uint256 outputValueA, uint256 outputValueB) = _addWethConvert(depositAmount, collateralRatio);

        rollUpRai = rai.balanceOf(address(rollupProcessor));

        uint256 bridgeTokensBalance = raiBridge.balanceOf(address(rollupProcessor));

        require(outputValueA > 0);

        require(outputValueA == rollUpRai, "Rai balance dont match");

        require(bridgeTokensBalance == rollUpRai, "Rai balance dont match bridgeTokens balance");
    }

    function _addWethConvert(uint256 depositAmount, uint256 collateralRatio)
        internal
        returns (uint256 outputValueA, uint256 outputValueB)
    {
        AztecTypes.AztecAsset memory empty;

        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(weth),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(rai),
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
            depositAmount,
            interactionNonce,
            collateralRatio
        );

        interactionNonce += 1;
    }

    function _assertCollateralRatio(uint256 rollUpRai) internal {
        // test the collateral ratio
        (, int256 x, , , ) = priceFeed.latestRoundData();
        uint256 raiToEth = uint256(x);
        uint256 actualCollateralRatio = totalDepositAmount.mul(1e22).div(raiToEth).div(rollUpRai);
        (uint256 expectedCollateralRatio, , ) = raiBridge.getSafeData();
        require(actualCollateralRatio == expectedCollateralRatio, "Collateral ratio not equal expected");
    }
}
