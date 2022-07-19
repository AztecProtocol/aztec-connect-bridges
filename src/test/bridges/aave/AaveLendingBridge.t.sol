// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

// Aztec specific imports
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {IDefiBridge} from "../../../aztec/interfaces/IDefiBridge.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";

// Aave-specific imports
import {IWETH} from "../../../interfaces/IWETH.sol";
import {ILendingPool} from "../../../interfaces/aave/ILendingPool.sol";
import {ILendingPoolAddressesProvider} from "../../../interfaces/aave/ILendingPoolAddressesProvider.sol";
import {IAaveIncentivesController} from "../../../interfaces/aave//IAaveIncentivesController.sol";
import {IAToken} from "../../../interfaces/aave/IAToken.sol";

import {DataTypes} from "../../../libraries/aave/DataTypes.sol";
import {WadRayMath} from "../../../libraries/aave/WadRayMath.sol";

import {IAccountingToken} from "../../../bridges/aave/interfaces/IAccountingToken.sol";
import {IAaveLendingBridge} from "../../../bridges/aave/lending/interfaces/IAaveLendingBridge.sol";
import {IAaveLendingBridgeConfigurator} from "../../../bridges/aave/lending/interfaces/IAaveLendingBridgeConfigurator.sol";
import {AaveLendingBridge} from "../../../bridges/aave/lending/AaveLendingBridge.sol";
import {AaveLendingBridgeConfigurator} from "../../../bridges/aave/lending/AaveLendingBridgeConfigurator.sol";

// Test specific imports
import {AaveV3StorageEmulator} from "./helpers/AaveV3StorageEmulator.sol";

library RoundingMath {
    function mulDiv(
        uint256 _a,
        uint256 _b,
        uint256 _c
    ) internal pure returns (uint256) {
        return (_a * _b) / _c;
    }
}

/**
 * @notice Tests for the Aave Lending Bridge
 * @dev Perform a mainnet fork to execute tests on.
 * Be aware, that test may fail if the node used is not of good quality, if tests fail, try a less "pressured" RPC
 * @author Lasse Herskind
 */
contract AaveLendingTest is BridgeTestBase {
    using RoundingMath for uint256;
    using WadRayMath for uint256;

    struct Balances {
        uint256 rollupEth;
        uint256 rollupToken;
        uint256 rollupZk;
        uint256 bridgeEth;
        uint256 bridgeToken;
        uint256 bridgeAToken;
        uint256 bridgeScaledAToken;
    }

    struct ExitWithTokenParams {
        uint256 index;
        uint256 innerATokenWithdraw;
        uint256 aaveInnerScaledChange;
        uint256 expectedScaledBalanceAfter;
        uint256 expectedScaledATokenBalanceAfter;
        uint256 expectedATokenBalanceAfter;
    }

    // Aave lending bridge specific storage
    ILendingPoolAddressesProvider internal constant ADDRESSES_PROVIDER =
        ILendingPoolAddressesProvider(0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5);
    IAaveIncentivesController internal constant INCENTIVES =
        IAaveIncentivesController(0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5);
    IERC20 internal constant STK_AAVE = IERC20(0x4da27a545c0c5B758a6BA100e3a049001de870f5);
    address internal constant BENEFICIARY = address(0xbe);

    ILendingPool internal pool = ILendingPool(ADDRESSES_PROVIDER.getLendingPool());

    IAaveLendingBridge internal aaveLendingBridge;
    uint256 internal id;
    IAaveLendingBridgeConfigurator internal configurator;
    bytes32 private constant LENDING_POOL = "LENDING_POOL";

    IERC20 internal constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 internal constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 internal constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 internal constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IWETH internal constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20[] internal tokens = [DAI, USDT, USDC, WBTC, IERC20(address(WETH))];

    // Test specific storage
    IERC20 internal token;
    IAToken internal aToken;
    // divisor and minValue is used to constrain deposit value to not be too large or too small.
    // minimum 1 whole token, maximum (2**128-1) / (10**(18 - aToken.decimals()))
    uint256 internal divisor;
    uint256 internal minValue;
    uint256 internal maxValue;

    function setUp() public {
        _setupLabels();

        configurator = IAaveLendingBridgeConfigurator(new AaveLendingBridgeConfigurator());

        aaveLendingBridge = IAaveLendingBridge(
            new AaveLendingBridge(address(ROLLUP_PROCESSOR), address(ADDRESSES_PROVIDER), address(configurator))
        );
        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(aaveLendingBridge), 500000);

        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();
    }

    function testReApproval() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokenSetup(tokens[i]);
            _addTokenToMapping();
            aaveLendingBridge.performApprovals(address(tokens[i]));
        }
        vm.expectRevert(ZkTokenDontExist.selector);
        aaveLendingBridge.performApprovals(address(0));
    }

    function testMintUnderlying() public {
        _tokenSetup(tokens[0]);
        _addTokenToMapping();
        address zkAToken = aaveLendingBridge.underlyingToZkAToken(address(tokens[0]));
        vm.expectRevert(InvalidCaller.selector);
        IAccountingToken(zkAToken).mint(address(this), 1);
    }

    function testAddTokensToMappingFromV2() public {
        emit log_named_address("Pool", address(pool));
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokenSetup(tokens[i]);
            emit log_named_address(aToken.name(), address(aToken));
            _addTokenToMapping();
        }
    }

    function testAddTokensToMappingFromV3() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokenSetup(tokens[i]);
            _addTokenToMappingV3();
        }
    }

    function testZKATokenNaming() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokenSetup(tokens[i]);
            _ZKATokenNaming();
        }
    }

    function testSanityConvert() public {
        _tokenSetup(WETH);
        AztecTypes.AztecAsset memory ethAsset = getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory daiAsset = getRealAztecAsset(address(DAI));
        AztecTypes.AztecAsset memory virtualAsset = AztecTypes.AztecAsset({
            id: 0,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.VIRTUAL
        });

        // Invalid caller //
        vm.expectRevert(InvalidCaller.selector);
        IDefiBridge(address(aaveLendingBridge)).convert(
            emptyAsset,
            emptyAsset,
            emptyAsset,
            emptyAsset,
            0,
            0,
            0,
            BENEFICIARY
        );

        vm.startPrank(address(ROLLUP_PROCESSOR));

        // Eth as input and output //
        vm.expectRevert(InputAssetAAndOutputAssetAIsEth.selector);
        IDefiBridge(address(aaveLendingBridge)).convert(
            ethAsset,
            emptyAsset,
            ethAsset,
            emptyAsset,
            0,
            0,
            0,
            BENEFICIARY
        );

        // Input asset empty
        vm.expectRevert(InputAssetANotERC20OrEth.selector);
        IDefiBridge(address(aaveLendingBridge)).convert(
            emptyAsset,
            emptyAsset,
            emptyAsset,
            emptyAsset,
            0,
            0,
            0,
            BENEFICIARY
        );

        // Input asset virtual
        vm.expectRevert(InputAssetANotERC20OrEth.selector);
        IDefiBridge(address(aaveLendingBridge)).convert(
            virtualAsset,
            emptyAsset,
            emptyAsset,
            emptyAsset,
            0,
            0,
            0,
            BENEFICIARY
        );

        // Output asset empty
        vm.expectRevert(OutputAssetANotERC20OrEth.selector);
        IDefiBridge(address(aaveLendingBridge)).convert(
            daiAsset,
            emptyAsset,
            emptyAsset,
            emptyAsset,
            0,
            0,
            0,
            BENEFICIARY
        );

        // Output asset virtual
        vm.expectRevert(OutputAssetANotERC20OrEth.selector);
        IDefiBridge(address(aaveLendingBridge)).convert(
            daiAsset,
            emptyAsset,
            virtualAsset,
            emptyAsset,
            0,
            0,
            0,
            BENEFICIARY
        );

        // Non empty input asset B
        vm.expectRevert(InputAssetBNotEmpty.selector);
        IDefiBridge(address(aaveLendingBridge)).convert(daiAsset, daiAsset, ethAsset, emptyAsset, 0, 0, 0, BENEFICIARY);
        vm.expectRevert(InputAssetBNotEmpty.selector);
        IDefiBridge(address(aaveLendingBridge)).convert(
            daiAsset,
            virtualAsset,
            ethAsset,
            emptyAsset,
            0,
            0,
            0,
            BENEFICIARY
        );
        vm.expectRevert(InputAssetBNotEmpty.selector);
        IDefiBridge(address(aaveLendingBridge)).convert(daiAsset, ethAsset, ethAsset, emptyAsset, 0, 0, 0, BENEFICIARY);

        // Non empty output asset B
        vm.expectRevert(OutputAssetBNotEmpty.selector);
        IDefiBridge(address(aaveLendingBridge)).convert(daiAsset, emptyAsset, ethAsset, daiAsset, 0, 0, 0, BENEFICIARY);
        vm.expectRevert(OutputAssetBNotEmpty.selector);
        IDefiBridge(address(aaveLendingBridge)).convert(
            daiAsset,
            emptyAsset,
            ethAsset,
            virtualAsset,
            0,
            0,
            0,
            BENEFICIARY
        );
        vm.expectRevert(OutputAssetBNotEmpty.selector);
        IDefiBridge(address(aaveLendingBridge)).convert(daiAsset, emptyAsset, ethAsset, ethAsset, 0, 0, 0, BENEFICIARY);

        // address(0) as input asset
        vm.expectRevert(InputAssetInvalid.selector);
        IDefiBridge(address(aaveLendingBridge)).convert(
            AztecTypes.AztecAsset({id: 2, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.ERC20}),
            emptyAsset,
            ethAsset,
            emptyAsset,
            0,
            0,
            0,
            BENEFICIARY
        );

        // address(0) as output asset
        vm.expectRevert(OutputAssetInvalid.selector);
        IDefiBridge(address(aaveLendingBridge)).convert(
            ethAsset,
            emptyAsset,
            AztecTypes.AztecAsset({id: 2, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.ERC20}),
            emptyAsset,
            0,
            0,
            0,
            BENEFICIARY
        );

        // Trying to enter with non-supported asset. Is assumed to be zkAtoken for exit,
        // Will revert because zkAToken for other tokens is address 0
        vm.expectRevert(InputAssetNotEqZkAToken.selector);
        IDefiBridge(address(aaveLendingBridge)).convert(
            daiAsset,
            emptyAsset,
            ethAsset,
            emptyAsset,
            0,
            0,
            0,
            BENEFICIARY
        );
    }

    function testFailEnterWithToken() public {
        _tokenSetup(DAI);
        _addTokenPool();
        _enterWithToken(0);
    }

    function testFailEnterWithEther() public {
        _tokenSetup(WETH);
        _addTokenPool();
        _enterWithEther(0);
    }

    function testEnterWithTokenBigValues() public {
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokenSetup(tokens[i]);
            _addTokenPool();
            _enterWithToken(maxValue);
        }
    }

    function testEnterWithEtherBigValues() public {
        _tokenSetup(WETH);
        _addTokenPool();
        _enterWithEther(maxValue);
    }

    function testFailExitPartially() public {
        _tokenSetup(DAI);
        _addTokenPool();
        _enterWithToken(100 ether / divisor);
        _accrueInterest(60 * 60 * 24);
        _exitWithToken(0);
    }

    function testFailExitPartiallyEther() public {
        _tokenSetup(WETH);
        _addTokenPool();
        _enterWithEther(100 ether / divisor);
        _accrueInterest(60 * 60 * 24);
        _exitWithEther(0);
    }

    function testEnterWithToken(uint128 _depositAmount, uint16 _timeDiff) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokenSetup(tokens[i]);
            _addTokenPool();
            _enterWithToken(bound(_depositAmount / divisor, minValue, maxValue));
            _accrueInterest(_timeDiff);
        }
    }

    function testEnterWithEther(uint128 _depositAmount, uint16 _timeDiff) public {
        _tokenSetup(WETH);
        _addTokenPool();
        _enterWithEther(bound(_depositAmount / divisor, minValue, maxValue));
        _accrueInterest(_timeDiff);
    }

    function testEnterWithNoEther() public {
        _tokenSetup(WETH);
        _addTokenPool();
        _enterWithEther(bound(0, minValue, maxValue));
        _accrueInterest(0);
    }

    function testAdditionalEnter(
        uint128 _depositAmount1,
        uint128 _depositAmount2,
        uint16 _timeDiff
    ) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokenSetup(tokens[i]);
            _addTokenPool();
            _enterWithToken(bound(_depositAmount1 / divisor, minValue, maxValue));
            _accrueInterest(_timeDiff);
            _enterWithToken(bound(_depositAmount2 / divisor, minValue, maxValue));
        }
    }

    function testAdditionalEnterEther(
        uint128 _depositAmount1,
        uint128 _depositAmount2,
        uint16 _timeDiff
    ) public {
        _tokenSetup(WETH);
        _addTokenPool();
        _enterWithEther(bound(_depositAmount1 / divisor, minValue, maxValue));
        _accrueInterest(_timeDiff);
        _enterWithEther(bound(_depositAmount2 / divisor, minValue, maxValue));
    }

    function testExitPartially(
        uint128 _depositAmount,
        uint128 _withdrawAmount,
        uint16 _timeDiff
    ) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokenSetup(tokens[i]);

            uint256 depositAmount = bound(_depositAmount / divisor, minValue, maxValue);
            uint256 index = pool.getReserveNormalizedIncome(address(token));
            uint256 scaledDepositAmount = uint256(depositAmount).rayDiv(index);

            _addTokenPool();
            _enterWithToken(depositAmount);
            _accrueInterest(_timeDiff);

            uint256 withdrawAmount = uint128(
                bound(_withdrawAmount, minValue.rayDiv(index) / 2, scaledDepositAmount / 2)
            );

            _exitWithToken(withdrawAmount);
        }
    }

    function testExitPartiallyEther(
        uint128 _depositAmount,
        uint128 _withdrawAmount,
        uint16 _timeDiff
    ) public {
        _tokenSetup(WETH);

        uint256 depositAmount = bound(_depositAmount / divisor, minValue, maxValue);
        uint256 index = pool.getReserveNormalizedIncome(address(token));
        uint256 scaledDepositAmount = uint256(depositAmount).rayDiv(index);

        _addTokenPool();
        _enterWithEther(depositAmount);
        _accrueInterest(_timeDiff);

        uint256 withdrawAmount = uint128(bound(_withdrawAmount, minValue.rayDiv(index) / 2, scaledDepositAmount / 2));

        _exitWithEther(withdrawAmount);
    }

    function testExitPartiallyThenCompletely(
        uint128 _depositAmount,
        uint16 _timeDiff1,
        uint16 _timeDiff2
    ) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokenSetup(tokens[i]);

            uint256 depositAmount = bound(_depositAmount / divisor, minValue, maxValue);

            _addTokenPool();
            _enterWithToken(depositAmount);

            _accrueInterest(_timeDiff1);

            _exitWithToken(depositAmount / 2);

            Balances memory balances = _getBalances();

            _accrueInterest(_timeDiff2);

            _exitWithToken(balances.rollupZk);

            Balances memory balancesAfter = _getBalances();

            assertLt(balances.rollupZk, depositAmount, "never entered, or entered at index = 1");
            assertEq(balancesAfter.rollupZk, 0, "Not exited with everything");
        }
    }

    function testExitPartiallyThenCompletelyEther(
        uint128 _depositAmount,
        uint16 _timeDiff1,
        uint16 _timeDiff2
    ) public {
        _tokenSetup(WETH);

        uint256 depositAmount = bound(_depositAmount / divisor, minValue, maxValue);

        _addTokenPool();
        _enterWithEther(depositAmount);

        _accrueInterest(_timeDiff1);

        _exitWithEther(depositAmount / 2);

        Balances memory balances = _getBalances();

        _accrueInterest(_timeDiff2);

        _exitWithEther(balances.rollupZk);

        Balances memory balancesAfter = _getBalances();

        assertLt(balances.rollupZk, depositAmount, "never entered, or entered at index = 1");
        assertEq(balancesAfter.rollupZk, 0, "Not exited with everything");
    }

    function testExitCompletely(uint128 _depositAmount, uint16 _timeDiff) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokenSetup(tokens[i]);

            _addTokenPool();
            uint256 depositAmount = bound(_depositAmount / divisor, minValue, maxValue);

            _enterWithToken(depositAmount);

            Balances memory balances = _getBalances();

            _accrueInterest(_timeDiff);

            _exitWithToken(balances.rollupZk);

            Balances memory balancesAfter = _getBalances();

            assertLt(balances.rollupZk, depositAmount, "entered at index = 1 RAY with and no interest accrual");
            assertEq(balancesAfter.rollupZk, 0, "Not exited with everything");
        }
    }

    function testExitCompletelyEther(uint128 _depositAmount, uint16 _timeDiff) public {
        _tokenSetup(WETH);

        _addTokenPool();
        uint256 depositAmount = bound(_depositAmount / divisor, minValue, maxValue);

        _enterWithEther(depositAmount);

        Balances memory balances = _getBalances();

        _accrueInterest(_timeDiff); // Ensure that some time have passed

        _exitWithEther(balances.rollupZk);

        Balances memory balancesAfter = _getBalances();

        assertLt(balances.rollupZk, depositAmount, "entered at index = 1 RAY with and no interest accrual");
        assertEq(balancesAfter.rollupZk, 0, "Not exited with everything");
    }

    function testClaimRewardstokenNotConfigurator(uint128 _depositAmount, uint16 _timeDiff) public {
        _tokenSetup(tokens[0]);

        _addTokenPool();
        _enterWithToken(bound(_depositAmount / divisor, minValue, maxValue));
        _accrueInterest(_timeDiff);

        address[] memory assets = new address[](1);
        assets[0] = address(aToken);

        vm.expectRevert(InvalidCaller.selector);
        aaveLendingBridge.claimLiquidityRewards(address(INCENTIVES), assets, BENEFICIARY);
        assertEq(STK_AAVE.balanceOf(address(aaveLendingBridge)), 0, "The bridge received the rewards");
        assertEq(STK_AAVE.balanceOf(address(BENEFICIARY)), 0, "The BENEFICIARY received the rewards");
    }

    function testClaimRewardsTokens(uint128 _depositAmount, uint16 _timeDiff) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokenSetup(tokens[i]);

            _addTokenPool();
            _enterWithToken(bound(_depositAmount / divisor, minValue, maxValue));
            _accrueInterest(_timeDiff);

            address[] memory assets = new address[](1);
            assets[0] = address(aToken);

            uint256 beneficiaryCurrentStakedAaveBalance = STK_AAVE.balanceOf(BENEFICIARY);

            uint256 expectedRewards = configurator.claimLiquidityRewards(
                address(aaveLendingBridge),
                address(INCENTIVES),
                assets,
                BENEFICIARY
            );
            assertEq(STK_AAVE.balanceOf(address(aaveLendingBridge)), 0, "The bridge received the rewards");

            // The claiming of liquidity rewards is not always returning the actual value increase
            assertApproxEqAbs(
                STK_AAVE.balanceOf(BENEFICIARY),
                expectedRewards + beneficiaryCurrentStakedAaveBalance,
                2
            );
        }
    }

    function testClaimRewardsEther(uint128 _depositAmount, uint16 _timeDiff) public {
        _tokenSetup(WETH);
        _addTokenPool();
        _enterWithEther(bound(_depositAmount / divisor, minValue, maxValue));
        _accrueInterest(_timeDiff);

        address[] memory assets = new address[](1);
        assets[0] = address(aToken);

        uint256 beneficiaryCurrentStakedAaveBalance = STK_AAVE.balanceOf(address(BENEFICIARY));
        uint256 expectedRewards = configurator.claimLiquidityRewards(
            address(aaveLendingBridge),
            address(INCENTIVES),
            assets,
            BENEFICIARY
        );
        assertEq(STK_AAVE.balanceOf(address(aaveLendingBridge)), 0, "The bridge received the rewards");

        // The claiming of liquidity rewards is not always returning the actual value increase
        assertApproxEqAbs(STK_AAVE.balanceOf(BENEFICIARY), expectedRewards + beneficiaryCurrentStakedAaveBalance, 2);
    }

    /// Helpers

    function _addTokenPool() internal {
        configurator.addPoolFromV2(address(aaveLendingBridge), address(token));

        // Add tokens if not supported already
        if (!isSupportedAsset(address(token))) {
            vm.prank(MULTI_SIG);
            ROLLUP_PROCESSOR.setSupportedAsset(address(token), 100000);
        }
        address zkToken = aaveLendingBridge.underlyingToZkAToken(address(token));
        if (!isSupportedAsset(address(zkToken))) {
            vm.prank(MULTI_SIG);
            ROLLUP_PROCESSOR.setSupportedAsset(address(zkToken), 100000);
        }
    }

    function _accrueInterest(uint256 _timeDiff) internal {
        // Will increase time with at least 24 hours to ensure that interest accrued is not rounded down.
        uint256 timeDiff = _timeDiff + 60 * 60 * 24;

        Balances memory balancesBefore = _getBalances();
        uint256 expectedTokenBefore = balancesBefore.rollupZk.rayMul(pool.getReserveNormalizedIncome(address(token)));

        vm.warp(block.timestamp + timeDiff);

        Balances memory balancesAfter = _getBalances();
        uint256 expectedTokenAfter = balancesAfter.rollupZk.rayMul(pool.getReserveNormalizedIncome(address(token)));

        if (timeDiff > 0) {
            assertGt(expectedTokenAfter, expectedTokenBefore, "Did not earn any interest");
        }

        // As we are rounding down. There will be excess dust in the bridge. Ensure that there is dust and that it is small
        assertLe(expectedTokenBefore, balancesBefore.bridgeAToken, "Bridge aToken not matching before time");
        assertLe(expectedTokenAfter, balancesAfter.bridgeAToken, "Bridge aToken not matching after time");

        assertApproxEqAbs(expectedTokenBefore, balancesBefore.bridgeAToken, 3);
        assertApproxEqAbs(expectedTokenAfter, balancesAfter.bridgeAToken, 3);
    }

    function _enterWithToken(uint256 _amount) internal {
        IERC20 zkAToken = IERC20(aaveLendingBridge.underlyingToZkAToken(address(token)));

        uint256 depositAmount = _amount;
        deal(address(token), address(ROLLUP_PROCESSOR), depositAmount);

        Balances memory balanceBefore = _getBalances();

        AztecTypes.AztecAsset memory inputAsset = getRealAztecAsset(address(token));
        AztecTypes.AztecAsset memory outputAsset = getRealAztecAsset(address(zkAToken));

        uint256 index = pool.getReserveNormalizedIncome(address(token));
        uint256 scaledDiffZk = depositAmount.mulDiv(1e27, index);
        uint256 expectedScaledBalanceAfter = balanceBefore.rollupZk + scaledDiffZk;

        uint256 bridgeCallData = encodeBridgeCallData(id, inputAsset, emptyAsset, outputAsset, emptyAsset, 0);
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(bridgeCallData, getNextNonce(), depositAmount, scaledDiffZk, 0, true, "");
        sendDefiRollup(bridgeCallData, depositAmount);

        Balances memory balanceAfter = _getBalances();

        assertEq(
            balanceAfter.rollupZk - balanceBefore.rollupZk,
            scaledDiffZk,
            "Scaled zkbalance balance change not matching"
        );
        assertEq(expectedScaledBalanceAfter, balanceAfter.rollupZk, "aToken balance not matching");

        {
            uint256 scaledDiffAToken = depositAmount.rayDiv(index);
            assertEq(
                balanceAfter.bridgeScaledAToken - balanceBefore.bridgeScaledAToken,
                scaledDiffAToken,
                "Scaled atoken balance change not matching"
            );

            assertLe(balanceBefore.rollupZk, balanceBefore.bridgeScaledAToken, "Scaled balances before not matching");
            assertLe(balanceAfter.rollupZk, balanceAfter.bridgeScaledAToken, "Scaled balances after not matching");

            uint256 expectedScaledATokenBalanceAfter = balanceBefore.bridgeScaledAToken + scaledDiffAToken;
            uint256 expectedATokenBalanceAfter = expectedScaledATokenBalanceAfter.rayMul(index);
            assertEq(
                expectedScaledATokenBalanceAfter,
                balanceAfter.bridgeScaledAToken,
                "scaled aToken balance not matching"
            );
            assertEq(expectedATokenBalanceAfter, balanceAfter.bridgeAToken, "aToken balance not matching");
        }

        assertEq(balanceBefore.rollupToken - balanceAfter.rollupToken, depositAmount, "Processor token not matching");
        assertEq(balanceBefore.bridgeToken, 0, "Bridge token balance before not matching");
        assertEq(balanceAfter.bridgeToken, 0, "Bridge token balance after not matching");
    }

    function _enterWithEther(uint256 _amount) internal {
        IERC20 zkAToken = IERC20(aaveLendingBridge.underlyingToZkAToken(address(WETH)));

        uint256 depositAmount = _amount;

        vm.deal(address(ROLLUP_PROCESSOR), depositAmount);

        Balances memory balanceBefore = _getBalances();

        AztecTypes.AztecAsset memory inputAsset = getRealAztecAsset(address(0));
        AztecTypes.AztecAsset memory outputAsset = getRealAztecAsset(address(zkAToken));

        uint256 index = pool.getReserveNormalizedIncome(address(token));
        uint256 scaledDiffZk = depositAmount.mulDiv(1e27, index);
        uint256 expectedScaledBalanceAfter = balanceBefore.rollupZk + scaledDiffZk;

        uint256 bridgeCallData = encodeBridgeCallData(id, inputAsset, emptyAsset, outputAsset, emptyAsset, 0);
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(bridgeCallData, getNextNonce(), depositAmount, scaledDiffZk, 0, true, "");
        sendDefiRollup(bridgeCallData, depositAmount);

        Balances memory balanceAfter = _getBalances();

        {
            assertEq(
                balanceAfter.rollupZk - balanceBefore.rollupZk,
                scaledDiffZk,
                "Scaled zkbalance balance change not matching"
            );

            uint256 expectedScaledBalanceAfter = balanceBefore.rollupZk + scaledDiffZk;
            assertEq(expectedScaledBalanceAfter, balanceAfter.rollupZk, "aToken balance not matching");
        }

        {
            uint256 scaledDiffAToken = depositAmount.rayDiv(index);
            assertEq(
                balanceAfter.bridgeScaledAToken - balanceBefore.bridgeScaledAToken,
                scaledDiffAToken,
                "Scaled atoken balance change not matching"
            );

            assertLe(balanceBefore.rollupZk, balanceBefore.bridgeScaledAToken, "Scaled balances before not matching");
            assertLe(balanceAfter.rollupZk, balanceAfter.bridgeScaledAToken, "Scaled balances after not matching");

            uint256 expectedScaledATokenBalanceAfter = balanceBefore.bridgeScaledAToken + scaledDiffAToken;
            uint256 expectedATokenBalanceAfter = expectedScaledATokenBalanceAfter.rayMul(index);
            assertEq(
                expectedScaledATokenBalanceAfter,
                balanceAfter.bridgeScaledAToken,
                "scaled aToken balance not matching"
            );
            assertEq(expectedATokenBalanceAfter, balanceAfter.bridgeAToken, "aToken balance not matching");
        }

        assertEq(balanceBefore.rollupEth - balanceAfter.rollupEth, depositAmount, "Processor token not matching");
        assertEq(balanceBefore.bridgeEth, 0, "Bridge eth balance before not matching");
        assertEq(balanceAfter.bridgeEth, 0, "Bridge eth balance after not matching");
    }

    function _exitWithToken(uint256 _zkAmount) internal {
        ExitWithTokenParams memory vars;

        IERC20 zkAToken = IERC20(aaveLendingBridge.underlyingToZkAToken(address(token)));

        uint256 withdrawAmount = _zkAmount;

        Balances memory balanceBefore = _getBalances();

        AztecTypes.AztecAsset memory inputAsset = getRealAztecAsset(address(zkAToken));
        AztecTypes.AztecAsset memory outputAsset = getRealAztecAsset(address(token));

        vars.index = pool.getReserveNormalizedIncome(address(token));
        vars.innerATokenWithdraw = withdrawAmount.mulDiv(vars.index, 1e27);
        vars.expectedScaledBalanceAfter = balanceBefore.rollupZk - withdrawAmount;

        uint256 bridgeCallData = encodeBridgeCallData(id, inputAsset, emptyAsset, outputAsset, emptyAsset, 0);
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(bridgeCallData, getNextNonce(), withdrawAmount, vars.innerATokenWithdraw, 0, true, "");
        sendDefiRollup(bridgeCallData, withdrawAmount);

        Balances memory balanceAfter = _getBalances();

        vars.aaveInnerScaledChange = vars.innerATokenWithdraw.rayDiv(vars.index);
        vars.expectedScaledATokenBalanceAfter = balanceBefore.bridgeScaledAToken - vars.aaveInnerScaledChange;
        vars.expectedATokenBalanceAfter = vars.expectedScaledATokenBalanceAfter.rayMul(vars.index);

        // Ensure that there are at least as much scaled aToken as zkAToken.
        assertLe(balanceBefore.rollupZk, balanceBefore.bridgeScaledAToken, "Scaled balances before not matching");
        assertLe(balanceAfter.rollupZk, balanceAfter.bridgeScaledAToken, "Scaled balances after not matching");

        assertEq(
            vars.expectedScaledATokenBalanceAfter,
            balanceAfter.bridgeScaledAToken,
            "Scaled balance after not matching"
        );
        assertEq(balanceAfter.rollupZk, vars.expectedScaledBalanceAfter, "Scaled balance after not matching");
        assertEq(
            balanceBefore.rollupZk - balanceAfter.rollupZk,
            withdrawAmount,
            "Change in zk balance is equal to deposit amount"
        );
        assertEq(
            balanceAfter.bridgeAToken,
            vars.expectedATokenBalanceAfter,
            "Bridge aToken balance don't match expected"
        );
        assertEq(
            balanceAfter.rollupToken,
            balanceBefore.rollupToken + vars.innerATokenWithdraw,
            "Rollup token balance don't match expected"
        );
    }

    function _exitWithEther(uint256 _zkAmount) internal {
        ExitWithTokenParams memory vars;

        IERC20 zkAToken = IERC20(aaveLendingBridge.underlyingToZkAToken(address(token)));

        uint256 withdrawAmount = _zkAmount;

        Balances memory balanceBefore = _getBalances();

        AztecTypes.AztecAsset memory inputAsset = getRealAztecAsset(address(zkAToken));
        AztecTypes.AztecAsset memory outputAsset = getRealAztecAsset(address(0));

        vars.index = pool.getReserveNormalizedIncome(address(token));
        vars.innerATokenWithdraw = withdrawAmount.mulDiv(vars.index, 1e27);
        vars.expectedScaledBalanceAfter = balanceBefore.rollupZk - withdrawAmount;

        uint256 bridgeCallData = encodeBridgeCallData(id, inputAsset, emptyAsset, outputAsset, emptyAsset, 0);
        vm.expectEmit(true, true, false, true);
        emit DefiBridgeProcessed(bridgeCallData, getNextNonce(), withdrawAmount, vars.innerATokenWithdraw, 0, true, "");
        sendDefiRollup(bridgeCallData, withdrawAmount);

        Balances memory balanceAfter = _getBalances();

        vars.aaveInnerScaledChange = vars.innerATokenWithdraw.rayDiv(vars.index);
        vars.expectedScaledBalanceAfter = balanceBefore.rollupZk - withdrawAmount;
        vars.expectedScaledATokenBalanceAfter = balanceBefore.bridgeScaledAToken - vars.aaveInnerScaledChange;
        vars.expectedATokenBalanceAfter = vars.expectedScaledATokenBalanceAfter.rayMul(vars.index);

        // Ensure that there are at least as much scaled aToken as zkAToken.
        assertLe(balanceBefore.rollupZk, balanceBefore.bridgeScaledAToken, "Scaled balances before not matching");
        assertLe(balanceAfter.rollupZk, balanceAfter.bridgeScaledAToken, "Scaled balances after not matching");

        assertEq(
            vars.expectedScaledATokenBalanceAfter,
            balanceAfter.bridgeScaledAToken,
            "Scaled balance after not matching"
        );
        assertEq(balanceAfter.rollupZk, vars.expectedScaledBalanceAfter, "Scaled balance after not matching");
        assertEq(
            balanceBefore.rollupZk - balanceAfter.rollupZk,
            withdrawAmount,
            "Change in zk balance is equal to deposit amount"
        );
        assertEq(
            balanceAfter.bridgeAToken,
            vars.expectedATokenBalanceAfter,
            "Bridge aToken balance don't match expected"
        );
        assertEq(
            balanceAfter.rollupEth,
            balanceBefore.rollupEth + vars.innerATokenWithdraw,
            "Rollup eth balance don't match expected"
        );
    }

    //solhint-disable-next-line
    function _ZKATokenNaming() internal {
        _addTokenPool();
        IERC20Metadata zkToken = IERC20Metadata(aaveLendingBridge.underlyingToZkAToken(address(token)));

        string memory name = string(abi.encodePacked("ZK-", aToken.name()));
        string memory symbol = string(abi.encodePacked("ZK-", aToken.symbol()));

        assertEq(zkToken.symbol(), symbol, "The zkAToken token symbol don't match");
        assertEq(zkToken.name(), name, "The zkAToken token name don't match");
        assertEq(zkToken.decimals(), aToken.decimals(), "The zkAToken token decimals don't match");
    }

    function _addTokenToMapping() internal {
        assertEq(aaveLendingBridge.underlyingToZkAToken(address(token)), address(0));

        // Add as not configurator (revert);
        vm.expectRevert(InvalidCaller.selector);
        aaveLendingBridge.setUnderlyingToZkAToken(address(token), address(token));

        // Add as invalid caller (revert)
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(0x1));
        configurator.addPoolFromV2(address(aaveLendingBridge), address(token));

        /// Add invalid (revert)
        vm.expectRevert(InvalidAToken.selector);
        configurator.addPoolFromV2(address(aaveLendingBridge), address(0xdead));

        /// Add invalid (revert)
        vm.expectRevert(InvalidAToken.selector);
        configurator.addNewPool(address(aaveLendingBridge), address(token), address(token));

        /// Add token as configurator
        configurator.addPoolFromV2(address(aaveLendingBridge), address(token));
        _assertNotEq(aaveLendingBridge.underlyingToZkAToken(address(token)), address(0));

        /// Add token again (revert)
        vm.expectRevert(ZkTokenAlreadyExists.selector);
        configurator.addPoolFromV2(address(aaveLendingBridge), address(token));
    }

    function _addTokenToMappingV3() internal {
        // Replaces the current implementation of the lendingpool with a mock implementation
        // that follows the V3 storage for reserveData + mock the data that is outputted
        address oldPool = ADDRESSES_PROVIDER.getLendingPool();
        address newCodeAddress = address(new AaveV3StorageEmulator(oldPool));

        bytes memory inputData = abi.encodeWithSelector(0x35ea6a75, address(token));

        //solhint-disable-next-line
        (bool success, bytes memory mockData) = newCodeAddress.call(inputData);
        if (!success) {
            revert("Cannot create mock data");
        }

        vm.prank(ADDRESSES_PROVIDER.owner());
        ADDRESSES_PROVIDER.setAddress(LENDING_POOL, newCodeAddress);
        _assertNotEq(ADDRESSES_PROVIDER.getLendingPool(), oldPool);

        address lendingPool = aaveLendingBridge.ADDRESSES_PROVIDER().getLendingPool();

        assertEq(aaveLendingBridge.underlyingToZkAToken(address(token)), address(0));

        // Add as not configurator (revert);
        vm.expectRevert(InvalidCaller.selector);
        aaveLendingBridge.setUnderlyingToZkAToken(address(token), address(token));

        /// Add invalid (revert)
        vm.mockCall(lendingPool, inputData, mockData);
        vm.expectRevert(InvalidAToken.selector);
        configurator.addPoolFromV3(address(aaveLendingBridge), address(0xdead));

        // Add as invalid caller (revert);
        vm.mockCall(lendingPool, inputData, mockData);
        vm.expectRevert("Ownable: caller is not the owner");
        vm.prank(address(0x01));
        configurator.addPoolFromV3(address(aaveLendingBridge), address(token));

        /// Add token as configurator
        vm.mockCall(lendingPool, inputData, mockData);
        configurator.addPoolFromV3(address(aaveLendingBridge), address(token));
        _assertNotEq(aaveLendingBridge.underlyingToZkAToken(address(token)), address(0));

        /// Add token again (revert)
        vm.expectRevert(ZkTokenAlreadyExists.selector);
        configurator.addPoolFromV3(address(aaveLendingBridge), address(token));

        vm.prank(ADDRESSES_PROVIDER.owner());
        ADDRESSES_PROVIDER.setAddress(LENDING_POOL, oldPool);
        assertEq(ADDRESSES_PROVIDER.getLendingPool(), oldPool, "Pool not reset");
    }

    function _assertNotEq(address _a, address _b) internal {
        if (_a == _b) {
            emit log("Error: a != b not satisfied [address]");
            emit log_named_address("  Expected", _b);
            emit log_named_address("    Actual", _a);
            fail();
        }
    }

    function _setupLabels() internal {
        vm.label(address(DAI), "DAI");
        vm.label(address(USDT), "USDT");
        vm.label(address(USDC), "USDC");
        vm.label(address(WBTC), "WBTC");
        vm.label(address(WETH), "WETH");
        vm.label(address(pool), "Pool");
    }

    function _tokenSetup(IERC20 _token) internal {
        token = _token;
        aToken = IAToken(pool.getReserveData(address(token)).aTokenAddress);
        minValue = 10**aToken.decimals();
        maxValue = 1e12 * 10**aToken.decimals();
        divisor = 10**(18 - aToken.decimals());

        vm.label(address(aToken), aToken.symbol());
    }

    function _getBalances() internal view returns (Balances memory) {
        IERC20 zkToken = IERC20(aaveLendingBridge.underlyingToZkAToken(address(token)));
        address rp = address(ROLLUP_PROCESSOR);
        address dbp = address(aaveLendingBridge);
        return
            Balances({
                rollupEth: rp.balance,
                rollupToken: token.balanceOf(rp),
                rollupZk: zkToken.balanceOf(rp),
                bridgeEth: dbp.balance,
                bridgeToken: token.balanceOf(dbp),
                bridgeAToken: aToken.balanceOf(dbp),
                bridgeScaledAToken: aToken.scaledBalanceOf(dbp)
            });
    }
}
