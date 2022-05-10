// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

// Aztec specific imports
import {DefiBridgeProxy} from '../../aztec/DefiBridgeProxy.sol';
import {RollupProcessor} from '../../aztec/RollupProcessor.sol';
import {AztecTypes} from '../../aztec/AztecTypes.sol';
import {IDefiBridge} from './../../interfaces/IDefiBridge.sol';

// Aave-specific imports
import {IWETH9} from '../../bridges/aave/imports/interfaces/IWETH9.sol';
import {ILendingPool} from '../../bridges/aave/imports/interfaces/ILendingPool.sol';
import {ILendingPoolAddressesProvider} from '../../bridges/aave/imports/interfaces/ILendingPoolAddressesProvider.sol';
import {IAaveIncentivesController} from '../../bridges/aave/imports/interfaces/IAaveIncentivesController.sol';
import {IAToken} from '../../bridges/aave/imports/interfaces/IAToken.sol';

import {DataTypes} from '../../bridges/aave/imports/libraries/DataTypes.sol';
import {WadRayMath} from '../../bridges/aave/imports/libraries/WadRayMath.sol';

import {IAaveLendingBridge} from '../../bridges/aave/lending/interfaces/IAaveLendingBridge.sol';
import {IAaveLendingBridgeConfigurator} from '../../bridges/aave/lending/interfaces/IAaveLendingBridgeConfigurator.sol';
import {AaveLendingBridge} from '../../bridges/aave/lending/AaveLendingBridge.sol';
import {AaveLendingBridgeConfigurator} from '../../bridges/aave/lending/AaveLendingBridgeConfigurator.sol';
import {Errors} from '../../bridges/aave/lending/libraries/Errors.sol';

// Test specific imports
import {AaveV3StorageEmulator} from './helpers/AaveV3StorageEmulator.sol';
import {TestHelper} from './helpers/TestHelper.sol';

/**
 * @notice Tests for the Aave Lending Bridge
 * @dev Perform a mainnet fork to execute tests on.
 * Be aware, that test may fail if the node used is not of good quality, if tests fail, try a less "pressured" RPC
 * @author Lasse Herskind
 */
contract AaveLendingTest is TestHelper {
    using WadRayMath for uint256;

    // Aztec defi bridge specific storage
    DefiBridgeProxy internal defiBridgeProxy;
    RollupProcessor internal rollupProcessor;

    // Aave lending bridge specific storage
    ILendingPoolAddressesProvider internal constant ADDRESSES_PROVIDER =
        ILendingPoolAddressesProvider(0xB53C1a33016B2DC2fF3653530bfF1848a515c8c5);
    IAaveIncentivesController internal constant INCENTIVES =
        IAaveIncentivesController(0xd784927Ff2f95ba542BfC824c8a8a98F3495f6b5);
    IERC20 internal constant STK_AAVE = IERC20(0x4da27a545c0c5B758a6BA100e3a049001de870f5);
    address internal constant BENEFICIARY = address(0xbe);

    ILendingPool internal pool = ILendingPool(ADDRESSES_PROVIDER.getLendingPool());

    IAaveLendingBridge internal aaveLendingBridge;
    IAaveLendingBridgeConfigurator internal configurator;
    bytes32 private constant LENDING_POOL = 'LENDING_POOL';

    IERC20 internal constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 internal constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 internal constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 internal constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IWETH9 internal constant WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20[] internal tokens = [DAI, USDT, USDC, WBTC, IERC20(address(WETH))];

    // Test specific storage
    IERC20 internal token;
    IAToken internal aToken;
    // divisor and minValue is used to constrain deposit value to not be too large or too small.
    // minimum 1 whole token, maximum (2**128-1) / (10**(18 - aToken.decimals()))
    uint256 internal divisor;
    uint256 internal minValue;
    uint256 internal maxValue;

    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    function _setupLabels() internal {
        VM.label(address(DAI), 'DAI');
        VM.label(address(USDT), 'USDT');
        VM.label(address(USDC), 'USDC');
        VM.label(address(WBTC), 'WBTC');
        VM.label(address(WETH), 'WETH');
        VM.label(address(pool), 'Pool');
    }

    function _tokenSetup(IERC20 _token) internal {
        token = _token;
        aToken = IAToken(pool.getReserveData(address(token)).aTokenAddress);
        minValue = 10**aToken.decimals();
        maxValue = 1e12 * 10**aToken.decimals();
        divisor = 10**(18 - aToken.decimals());
    }

    function setUp() public {
        _aztecPreSetup();
        _setupLabels();

        configurator = IAaveLendingBridgeConfigurator(new AaveLendingBridgeConfigurator());

        aaveLendingBridge = IAaveLendingBridge(
            new AaveLendingBridge(address(rollupProcessor), address(ADDRESSES_PROVIDER), address(configurator))
        );
    }

    function testAddTokensToMappingFromV2() public {
        emit log_named_address('Pool', address(pool));
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
        AztecTypes.AztecAsset memory emptyAsset = AztecTypes.AztecAsset({
            id: 0,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.NOT_USED
        });
        AztecTypes.AztecAsset memory ethAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.ETH
        });
        AztecTypes.AztecAsset memory daiAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(DAI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory virtualAsset = AztecTypes.AztecAsset({
            id: 3,
            erc20Address: address(0xda),
            assetType: AztecTypes.AztecAssetType.VIRTUAL
        });

        // Invalid caller //
        VM.expectRevert(bytes(Errors.INVALID_CALLER));
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

        VM.startPrank(address(rollupProcessor));

        // Eth as input and output //
        VM.expectRevert(bytes(Errors.INPUT_ASSET_A_AND_OUTPUT_ASSET_A_IS_ETH));
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
        VM.expectRevert(bytes(Errors.INPUT_ASSET_A_NOT_ERC20_OR_ETH));
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
        VM.expectRevert(bytes(Errors.INPUT_ASSET_A_NOT_ERC20_OR_ETH));
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
        VM.expectRevert(bytes(Errors.OUTPUT_ASSET_A_NOT_ERC20_OR_ETH));
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
        VM.expectRevert(bytes(Errors.OUTPUT_ASSET_A_NOT_ERC20_OR_ETH));
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
        VM.expectRevert(bytes(Errors.INPUT_ASSET_B_NOT_EMPTY));
        IDefiBridge(address(aaveLendingBridge)).convert(daiAsset, daiAsset, ethAsset, emptyAsset, 0, 0, 0, BENEFICIARY);
        VM.expectRevert(bytes(Errors.INPUT_ASSET_B_NOT_EMPTY));
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
        VM.expectRevert(bytes(Errors.INPUT_ASSET_B_NOT_EMPTY));
        IDefiBridge(address(aaveLendingBridge)).convert(daiAsset, ethAsset, ethAsset, emptyAsset, 0, 0, 0, BENEFICIARY);

        // Non empty output asset B
        VM.expectRevert(bytes(Errors.OUTPUT_ASSET_B_NOT_EMPTY));
        IDefiBridge(address(aaveLendingBridge)).convert(daiAsset, emptyAsset, ethAsset, daiAsset, 0, 0, 0, BENEFICIARY);
        VM.expectRevert(bytes(Errors.OUTPUT_ASSET_B_NOT_EMPTY));
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
        VM.expectRevert(bytes(Errors.OUTPUT_ASSET_B_NOT_EMPTY));
        IDefiBridge(address(aaveLendingBridge)).convert(daiAsset, emptyAsset, ethAsset, ethAsset, 0, 0, 0, BENEFICIARY);

        // address(0) as input asset
        VM.expectRevert(bytes(Errors.INPUT_ASSET_INVALID));
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
        VM.expectRevert(bytes(Errors.OUTPUT_ASSET_INVALID));
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
        VM.expectRevert(bytes(Errors.INPUT_ASSET_NOT_EQ_ZK_ATOKEN));
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

    function testEnterWithToken(uint128 depositAmount, uint16 timeDiff) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokenSetup(tokens[i]);
            _addTokenPool();
            _enterWithToken(bound(depositAmount / divisor, minValue, maxValue));
            _accrueInterest(timeDiff);
        }
    }

    function testEnterWithEther(uint128 depositAmount, uint16 timeDiff) public {
        _tokenSetup(WETH);
        _addTokenPool();
        _enterWithEther(bound(depositAmount / divisor, minValue, maxValue));
        _accrueInterest(timeDiff);
    }

    function testEnterWithNoEther() public {
        _tokenSetup(WETH);
        _addTokenPool();
        _enterWithEther(bound(0, minValue, maxValue));
        _accrueInterest(0);
    }

    function testAdditionalEnter(
        uint128 depositAmount1,
        uint128 depositAmount2,
        uint16 timeDiff
    ) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokenSetup(tokens[i]);
            _addTokenPool();
            _enterWithToken(bound(depositAmount1 / divisor, minValue, maxValue));
            _accrueInterest(timeDiff);
            _enterWithToken(bound(depositAmount2 / divisor, minValue, maxValue));
        }
    }

    function testAdditionalEnterEther(
        uint128 depositAmount1,
        uint128 depositAmount2,
        uint16 timeDiff
    ) public {
        _tokenSetup(WETH);
        _addTokenPool();
        _enterWithEther(bound(depositAmount1 / divisor, minValue, maxValue));
        _accrueInterest(timeDiff);
        _enterWithEther(bound(depositAmount2 / divisor, minValue, maxValue));
    }

    function testExitPartially(
        uint128 _depositAmount,
        uint128 withdrawAmount,
        uint16 timeDiff
    ) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokenSetup(tokens[i]);

            uint256 depositAmount = bound(_depositAmount / divisor, minValue, maxValue);
            uint256 index = pool.getReserveNormalizedIncome(address(token));
            uint256 scaledDepositAmount = uint256(depositAmount).rayDiv(index);

            _addTokenPool();
            _enterWithToken(depositAmount);
            _accrueInterest(timeDiff);

            withdrawAmount = uint128(bound(withdrawAmount, minValue.rayDiv(index) / 2, scaledDepositAmount / 2));

            _exitWithToken(withdrawAmount);
        }
    }

    function testExitPartiallyEther(
        uint128 _depositAmount,
        uint128 withdrawAmount,
        uint16 timeDiff
    ) public {
        _tokenSetup(WETH);

        uint256 depositAmount = bound(_depositAmount / divisor, minValue, maxValue);
        uint256 index = pool.getReserveNormalizedIncome(address(token));
        uint256 scaledDepositAmount = uint256(depositAmount).rayDiv(index);

        _addTokenPool();
        _enterWithEther(depositAmount);
        _accrueInterest(timeDiff);

        withdrawAmount = uint128(bound(withdrawAmount, minValue.rayDiv(index) / 2, scaledDepositAmount / 2));

        _exitWithEther(withdrawAmount);
    }

    function testExitPartiallyThenCompletely(
        uint128 _depositAmount,
        uint16 timeDiff1,
        uint16 timeDiff2
    ) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokenSetup(tokens[i]);

            uint256 depositAmount = bound(_depositAmount / divisor, minValue, maxValue);

            _addTokenPool();
            _enterWithToken(depositAmount);

            _accrueInterest(timeDiff1);

            _exitWithToken(depositAmount / 2);

            Balances memory balances = _getBalances();

            _accrueInterest(timeDiff2);

            _exitWithToken(balances.rollupZk);

            Balances memory balancesAfter = _getBalances();

            assertLt(balances.rollupZk, depositAmount, 'never entered, or entered at index = 1');
            assertEq(balancesAfter.rollupZk, 0, 'Not exited with everything');
        }
    }

    function testExitPartiallyThenCompletelyEther(
        uint128 _depositAmount,
        uint16 timeDiff1,
        uint16 timeDiff2
    ) public {
        _tokenSetup(WETH);

        uint256 depositAmount = bound(_depositAmount / divisor, minValue, maxValue);

        _addTokenPool();
        _enterWithEther(depositAmount);

        _accrueInterest(timeDiff1);

        _exitWithEther(depositAmount / 2);

        Balances memory balances = _getBalances();

        _accrueInterest(timeDiff2);

        _exitWithEther(balances.rollupZk);

        Balances memory balancesAfter = _getBalances();

        assertLt(balances.rollupZk, depositAmount, 'never entered, or entered at index = 1');
        assertEq(balancesAfter.rollupZk, 0, 'Not exited with everything');
    }

    function testExitCompletely(uint128 _depositAmount, uint16 timeDiff) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokenSetup(tokens[i]);

            _addTokenPool();
            uint256 depositAmount = bound(_depositAmount / divisor, minValue, maxValue);

            _enterWithToken(depositAmount);

            Balances memory balances = _getBalances();

            _accrueInterest(timeDiff);

            _exitWithToken(balances.rollupZk);

            Balances memory balancesAfter = _getBalances();

            assertLt(balances.rollupZk, depositAmount, 'entered at index = 1 RAY with and no interest accrual');
            assertEq(balancesAfter.rollupZk, 0, 'Not exited with everything');
        }
    }

    function testExitCompletelyEther(uint128 _depositAmount, uint16 timeDiff) public {
        _tokenSetup(WETH);

        _addTokenPool();
        uint256 depositAmount = bound(_depositAmount / divisor, minValue, maxValue);

        _enterWithEther(depositAmount);

        Balances memory balances = _getBalances();

        _accrueInterest(timeDiff); // Ensure that some time have passed

        _exitWithEther(balances.rollupZk);

        Balances memory balancesAfter = _getBalances();

        assertLt(balances.rollupZk, depositAmount, 'entered at index = 1 RAY with and no interest accrual');
        assertEq(balancesAfter.rollupZk, 0, 'Not exited with everything');
    }

    function testClaimRewardstokenNotConfigurator(uint128 depositAmount, uint16 timeDiff) public {
        _tokenSetup(tokens[0]);

        _addTokenPool();
        _enterWithToken(bound(depositAmount / divisor, minValue, maxValue));
        _accrueInterest(timeDiff);

        address[] memory assets = new address[](1);
        assets[0] = address(aToken);

        VM.expectRevert(bytes(Errors.INVALID_CALLER));
        aaveLendingBridge.claimLiquidityRewards(address(INCENTIVES), assets, BENEFICIARY);
        assertEq(STK_AAVE.balanceOf(address(aaveLendingBridge)), 0, 'The bridge received the rewards');
        assertEq(STK_AAVE.balanceOf(address(BENEFICIARY)), 0, 'The BENEFICIARY received the rewards');
    }

    function testClaimRewardsTokens(uint128 depositAmount, uint16 timeDiff) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            _tokenSetup(tokens[i]);

            _addTokenPool();
            _enterWithToken(bound(depositAmount / divisor, minValue, maxValue));
            _accrueInterest(timeDiff);

            address[] memory assets = new address[](1);
            assets[0] = address(aToken);

            uint256 beneficiaryCurrentStakedAaveBalance = STK_AAVE.balanceOf(BENEFICIARY);

            uint256 expectedRewards = configurator.claimLiquidityRewards(
                address(aaveLendingBridge),
                address(INCENTIVES),
                assets,
                BENEFICIARY
            );
            assertEq(STK_AAVE.balanceOf(address(aaveLendingBridge)), 0, 'The bridge received the rewards');

            // The claiming of liquidity rewards is not always returning the actual value increase
            assertApproxEq(STK_AAVE.balanceOf(BENEFICIARY), expectedRewards + beneficiaryCurrentStakedAaveBalance, 2);
        }
    }

    function testClaimRewardsEther(uint128 depositAmount, uint16 timeDiff) public {
        _tokenSetup(WETH);
        _addTokenPool();
        _enterWithEther(bound(depositAmount / divisor, minValue, maxValue));
        _accrueInterest(timeDiff);

        address[] memory assets = new address[](1);
        assets[0] = address(aToken);

        uint256 beneficiaryCurrentStakedAaveBalance = STK_AAVE.balanceOf(address(BENEFICIARY));
        uint256 expectedRewards = configurator.claimLiquidityRewards(
            address(aaveLendingBridge),
            address(INCENTIVES),
            assets,
            BENEFICIARY
        );
        assertEq(STK_AAVE.balanceOf(address(aaveLendingBridge)), 0, 'The bridge received the rewards');

        // The claiming of liquidity rewards is not always returning the actual value increase
        assertApproxEq(STK_AAVE.balanceOf(BENEFICIARY), expectedRewards + beneficiaryCurrentStakedAaveBalance, 2);
    }

    /// Helpers

    function _addTokenPool() internal {
        configurator.addPoolFromV2(address(aaveLendingBridge), address(token));
    }

    struct Balances {
        uint256 rollupEth;
        uint256 rollupToken;
        uint256 rollupZk;
        uint256 bridgeEth;
        uint256 bridgeToken;
        uint256 bridgeAToken;
        uint256 bridgeScaledAToken;
    }

    function _getBalances() internal view returns (Balances memory) {
        IERC20 zkToken = IERC20(aaveLendingBridge.underlyingToZkAToken(address(token)));
        address rp = address(rollupProcessor);
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

    function _accrueInterest(uint256 timeDiff) internal {
        // Will increase time with at least 24 hours to ensure that interest accrued is not rounded down.
        timeDiff = timeDiff + 60 * 60 * 24;

        Balances memory balancesBefore = _getBalances();
        uint256 expectedTokenBefore = balancesBefore.rollupZk.rayMul(pool.getReserveNormalizedIncome(address(token)));

        VM.warp(block.timestamp + timeDiff);

        Balances memory balancesAfter = _getBalances();
        uint256 expectedTokenAfter = balancesAfter.rollupZk.rayMul(pool.getReserveNormalizedIncome(address(token)));

        if (timeDiff > 0) {
            assertGt(expectedTokenAfter, expectedTokenBefore, 'Did not earn any interest');
        }

        assertEq(expectedTokenBefore, balancesBefore.bridgeAToken, 'Bridge aToken not matching before time');
        assertEq(expectedTokenAfter, balancesAfter.bridgeAToken, 'Bridge aToken not matching after time');
    }

    function _enterWithToken(uint256 amount) public {
        IERC20 zkAToken = IERC20(aaveLendingBridge.underlyingToZkAToken(address(token)));

        uint256 depositAmount = amount;
        _setTokenBalance(address(token), address(rollupProcessor), depositAmount);

        Balances memory balanceBefore = _getBalances();

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(token),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(zkAToken),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = rollupProcessor.convert(
            address(aaveLendingBridge),
            inputAsset,
            empty,
            outputAsset,
            empty,
            depositAmount,
            1,
            0
        );

        assertFalse(isAsync, 'Convert is async');
        assertEq(outputValueB, 0, 'OutputValue B not zero');

        Balances memory balanceAfter = _getBalances();

        uint256 index = pool.getReserveNormalizedIncome(address(token));
        uint256 scaledDiff = depositAmount.rayDiv(index);
        uint256 expectedScaledBalanceAfter = balanceBefore.rollupZk + scaledDiff;
        uint256 expectedATokenBalanceAfter = expectedScaledBalanceAfter.rayMul(index);
        assertEq(balanceBefore.rollupZk, balanceBefore.bridgeScaledAToken, 'Scaled balances before not matching');
        assertEq(balanceAfter.rollupZk, balanceAfter.bridgeScaledAToken, 'Scaled balances after not matching');
        assertEq(
            balanceAfter.rollupZk - balanceBefore.rollupZk,
            outputValueA,
            'Output value and zk balance not matching'
        );
        assertEq(balanceAfter.rollupZk - balanceBefore.rollupZk, scaledDiff, 'Scaled balance change not matching');
        assertEq(expectedATokenBalanceAfter, balanceAfter.bridgeAToken, 'aToken balance not matching');
        assertEq(balanceBefore.rollupToken - balanceAfter.rollupToken, depositAmount, 'Processor token not matching');
        assertEq(balanceBefore.bridgeToken, 0, 'Bridge token balance before not matching');
        assertEq(balanceAfter.bridgeToken, 0, 'Bridge token balance after not matching');
    }

    function _enterWithEther(uint256 amount) public {
        IERC20 zkAToken = IERC20(aaveLendingBridge.underlyingToZkAToken(address(WETH)));

        uint256 depositAmount = amount;

        VM.deal(address(rollupProcessor), depositAmount);

        Balances memory balanceBefore = _getBalances();

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.ETH
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(zkAToken),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = rollupProcessor.convert(
            address(aaveLendingBridge),
            inputAsset,
            empty,
            outputAsset,
            empty,
            depositAmount,
            1,
            0
        );
        assertFalse(isAsync, 'Convert is async');
        assertEq(outputValueB, 0, 'OutputValue B not zero');

        Balances memory balanceAfter = _getBalances();

        uint256 index = pool.getReserveNormalizedIncome(address(token));
        uint256 scaledDiff = depositAmount.rayDiv(index);
        uint256 expectedScaledBalanceAfter = balanceBefore.rollupZk + scaledDiff;
        uint256 expectedATokenBalanceAfter = expectedScaledBalanceAfter.rayMul(index);

        assertEq(balanceBefore.rollupZk, balanceBefore.bridgeScaledAToken, 'Scaled balances before not matching');
        assertEq(balanceAfter.rollupZk, balanceAfter.bridgeScaledAToken, 'Scaled balances after not matching');
        assertEq(
            balanceAfter.rollupZk - balanceBefore.rollupZk,
            outputValueA,
            'Output value and zk balance not matching'
        );
        assertEq(balanceAfter.rollupZk - balanceBefore.rollupZk, scaledDiff, 'Scaled balance change not matching');
        assertEq(expectedATokenBalanceAfter, balanceAfter.bridgeAToken, 'aToken balance not matching');
        assertEq(balanceBefore.rollupEth - balanceAfter.rollupEth, depositAmount, 'Processor eth not matching');
        assertEq(balanceBefore.bridgeEth, 0, 'Bridge eth balance before not matching');
        assertEq(balanceAfter.bridgeEth, 0, 'Bridge eth balance after not matching');
    }

    struct exitWithTokenParams {
        uint256 index;
        uint256 innerATokenWithdraw;
        uint256 innerScaledChange;
        uint256 expectedScaledBalanceAfter;
        uint256 expectedATokenBalanceAfter;
    }

    function _exitWithToken(uint256 zkAmount) public {
        exitWithTokenParams memory vars;

        IERC20 zkAToken = IERC20(aaveLendingBridge.underlyingToZkAToken(address(token)));

        uint256 withdrawAmount = zkAmount;

        Balances memory balanceBefore = _getBalances();

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(zkAToken),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(token),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = rollupProcessor.convert(
            address(aaveLendingBridge),
            inputAsset,
            empty,
            outputAsset,
            empty,
            withdrawAmount,
            2,
            0
        );
        assertFalse(isAsync, 'Convert is async');
        assertEq(outputValueB, 0, 'OutputValue B not zero');

        Balances memory balanceAfter = _getBalances();

        vars.index = pool.getReserveNormalizedIncome(address(token));
        vars.innerATokenWithdraw = withdrawAmount.rayMul(vars.index);
        vars.innerScaledChange = vars.innerATokenWithdraw.rayDiv(vars.index);

        vars.expectedScaledBalanceAfter = balanceBefore.rollupZk - withdrawAmount;

        vars.expectedATokenBalanceAfter = vars.expectedScaledBalanceAfter.rayMul(vars.index);

        assertEq(withdrawAmount, vars.innerScaledChange, 'Inner not matching');

        assertEq(vars.innerATokenWithdraw, outputValueA, 'Output token does not match expected output');
        assertEq(balanceBefore.rollupZk, balanceBefore.bridgeScaledAToken, 'Scaled balance before not matching');
        assertEq(balanceAfter.rollupZk, balanceAfter.bridgeScaledAToken, 'Scaled balance after not matching');
        assertEq(balanceAfter.rollupZk, vars.expectedScaledBalanceAfter, 'Scaled balance after not matching');
        assertEq(
            balanceBefore.rollupZk - balanceAfter.rollupZk,
            withdrawAmount,
            'Change in zk balance is equal to deposit amount'
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

    function _exitWithEther(uint256 zkAmount) public {
        exitWithTokenParams memory vars;

        IERC20 zkAToken = IERC20(aaveLendingBridge.underlyingToZkAToken(address(token)));

        uint256 withdrawAmount = zkAmount;

        Balances memory balanceBefore = _getBalances();

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory inputAsset = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(zkAToken),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.ETH
        });

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = rollupProcessor.convert(
            address(aaveLendingBridge),
            inputAsset,
            empty,
            outputAsset,
            empty,
            withdrawAmount,
            2,
            0
        );
        assertFalse(isAsync, 'Convert is async');
        assertEq(outputValueB, 0, 'OutputValue B not zero');

        Balances memory balanceAfter = _getBalances();

        vars.index = pool.getReserveNormalizedIncome(address(token));
        vars.innerATokenWithdraw = withdrawAmount.rayMul(vars.index);
        vars.innerScaledChange = vars.innerATokenWithdraw.rayDiv(vars.index);

        vars.expectedScaledBalanceAfter = balanceBefore.rollupZk - withdrawAmount;

        vars.expectedATokenBalanceAfter = vars.expectedScaledBalanceAfter.rayMul(vars.index);

        assertEq(withdrawAmount, vars.innerScaledChange, 'Inner not matching');

        assertEq(vars.innerATokenWithdraw, outputValueA, 'Output token does not match expected output');
        assertEq(balanceBefore.rollupZk, balanceBefore.bridgeScaledAToken, 'Scaled balance before not matching');
        assertEq(balanceAfter.rollupZk, balanceAfter.bridgeScaledAToken, 'Scaled balance after not matching');
        assertEq(balanceAfter.rollupZk, vars.expectedScaledBalanceAfter, 'Scaled balance after not matching');
        assertEq(
            balanceBefore.rollupZk - balanceAfter.rollupZk,
            withdrawAmount,
            'Change in zk balance is equal to deposit amount'
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

    function _ZKATokenNaming() public {
        _addTokenPool();
        IERC20Metadata zkToken = IERC20Metadata(aaveLendingBridge.underlyingToZkAToken(address(token)));

        string memory name = string(abi.encodePacked('ZK-', aToken.name()));
        string memory symbol = string(abi.encodePacked('ZK-', aToken.symbol()));

        assertEq(zkToken.symbol(), symbol, "The zkAToken token symbol don't match");
        assertEq(zkToken.name(), name, "The zkAToken token name don't match");
        assertEq(zkToken.decimals(), aToken.decimals(), "The zkAToken token decimals don't match");
    }

    function _addTokenToMapping() public {
        assertEq(aaveLendingBridge.underlyingToZkAToken(address(token)), address(0));

        // Add as not configurator (revert);
        VM.expectRevert(bytes(Errors.INVALID_CALLER));
        aaveLendingBridge.setUnderlyingToZkAToken(address(token), address(token));

        // Add as invalid caller (revert)
        VM.expectRevert('Ownable: caller is not the owner');
        VM.prank(address(0x1));
        configurator.addPoolFromV2(address(aaveLendingBridge), address(token));

        /// Add invalid (revert)
        VM.expectRevert(bytes(Errors.INVALID_ATOKEN));
        configurator.addPoolFromV2(address(aaveLendingBridge), address(0xdead));

        /// Add invalid (revert)
        VM.expectRevert(bytes(Errors.INVALID_ATOKEN));
        configurator.addNewPool(address(aaveLendingBridge), address(token), address(token));

        /// Add token as configurator
        configurator.addPoolFromV2(address(aaveLendingBridge), address(token));
        assertNotEq(aaveLendingBridge.underlyingToZkAToken(address(token)), address(0));

        /// Add token again (revert)
        VM.expectRevert(bytes(Errors.ZK_TOKEN_ALREADY_SET));
        configurator.addPoolFromV2(address(aaveLendingBridge), address(token));
    }

    function _addTokenToMappingV3() public {
        // Replaces the current implementation of the lendingpool with a mock implementation
        // that follows the V3 storage for reserveData + mock the data that is outputted
        address oldPool = ADDRESSES_PROVIDER.getLendingPool();
        address newCodeAddress = address(new AaveV3StorageEmulator(oldPool));

        bytes memory inputData = abi.encodeWithSelector(0x35ea6a75, address(token));
        (bool success, bytes memory mockData) = newCodeAddress.call(inputData);
        require(success, 'Cannot create mock data');

        VM.prank(ADDRESSES_PROVIDER.owner());
        ADDRESSES_PROVIDER.setAddress(LENDING_POOL, newCodeAddress);
        assertNotEq(ADDRESSES_PROVIDER.getLendingPool(), oldPool);

        address lendingPool = aaveLendingBridge.ADDRESSES_PROVIDER().getLendingPool();

        assertEq(aaveLendingBridge.underlyingToZkAToken(address(token)), address(0));

        // Add as not configurator (revert);
        VM.expectRevert(bytes(Errors.INVALID_CALLER));
        aaveLendingBridge.setUnderlyingToZkAToken(address(token), address(token));

        /// Add invalid (revert)
        VM.mockCall(lendingPool, inputData, mockData);
        VM.expectRevert(bytes(Errors.INVALID_ATOKEN));
        configurator.addPoolFromV3(address(aaveLendingBridge), address(0xdead));

        // Add as invalid caller (revert);
        VM.mockCall(lendingPool, inputData, mockData);
        VM.expectRevert('Ownable: caller is not the owner');
        VM.prank(address(0x01));
        configurator.addPoolFromV3(address(aaveLendingBridge), address(token));

        /// Add token as configurator
        VM.mockCall(lendingPool, inputData, mockData);
        configurator.addPoolFromV3(address(aaveLendingBridge), address(token));
        assertNotEq(aaveLendingBridge.underlyingToZkAToken(address(token)), address(0));

        /// Add token again (revert)
        VM.expectRevert(bytes(Errors.ZK_TOKEN_ALREADY_SET));
        configurator.addPoolFromV3(address(aaveLendingBridge), address(token));

        VM.prank(ADDRESSES_PROVIDER.owner());
        ADDRESSES_PROVIDER.setAddress(LENDING_POOL, oldPool);
        assertEq(ADDRESSES_PROVIDER.getLendingPool(), oldPool, 'Pool not reset');
    }
}
