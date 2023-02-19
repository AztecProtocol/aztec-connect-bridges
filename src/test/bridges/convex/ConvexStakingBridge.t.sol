// SPDX-License-Identifier: Apache-2.0

pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ConvexStakingBridge} from "../../../bridges/convex/ConvexStakingBridge.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {IConvexBooster} from "../../../interfaces/convex/IConvexBooster.sol";
import {ICurveRewards} from "../../../interfaces/convex/ICurveRewards.sol";
import {IRepConvexToken} from "../../../interfaces/convex/IRepConvexToken.sol";
import {ICurveLiquidityPool} from "../../../interfaces/convex/ICurveLiquidityPool.sol";
import {InflationProtection} from "../../../libraries/convex/InflationProtection.sol";

contract ConvexStakingBridgeTest is BridgeTestBase {
    address private constant BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address private constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address private constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address private constant BENEFICIARY = address(777);
    address private constant BOOSTER_POOL_MANAGER = 0x5F47010F230cE1568BeA53a06eBAF528D05c5c1B;

    address private curveLpToken;
    address private convexLpToken;
    address private rctImplementation;
    address private rctClone;
    address private staker;
    address private gauge;
    address private stash;
    address private curveRewards;
    address private minter;
    address private rollupProcessor;
    ConvexStakingBridge private bridge;

    uint256[10] public supportedPids = [23, 25, 32, 33, 38, 40, 49, 61, 64, 122];

    error UnsupportedPool(uint256 poolId);
    error PoolAlreadyLoaded(uint256 poolId);
    error InsufficientFirstDepositAmount();

    function receiveEthFromBridge(uint256 _interactionNonce) external payable {}

    function setUp() public {
        rollupProcessor = address(this);
        staker = IConvexBooster(BOOSTER).staker();
        minter = IConvexBooster(BOOSTER).minter();

        // labels
        vm.label(address(this), "Test Contract");
        vm.label(address(msg.sender), "Test Contract Msg Sender");
        vm.label(BOOSTER, "Booster");
        vm.label(staker, "Staker Contract Address");
        vm.label(minter, "Minter");
        vm.label(CRV, "Reward boosted CRV Token");
        vm.label(CVX, "Reward CVX Token");
        vm.label(BENEFICIARY, "Beneficiary");
    }

    function testInvalidInput(uint256 _poolId) public {
        address invalidCurveLpToken = address(123);
        uint256 depositAmount = 1e16;
        uint256 poolId = _getPoolId(_poolId);

        // labels
        vm.label(invalidCurveLpToken, "Invalid Curve LP Token Address");

        _setupBridge(poolId);
        _loadPool(poolId);
        _setupRepresentingConvexTokenClone();

        vm.expectRevert(ErrorLib.InvalidInput.selector);
        bridge.convert(
            AztecTypes.AztecAsset(1, invalidCurveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(100, rctClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            depositAmount,
            0,
            0,
            BENEFICIARY
        );
    }

    function testInvalidInputAssetType(uint256 _poolId) public {
        address invalidCurveLpToken = address(123);
        uint256 depositAmount = 1e16;
        uint256 poolId = _getPoolId(_poolId);

        // labels
        vm.label(invalidCurveLpToken, "Invalid Curve LP Token Address");

        _setupBridge(poolId);
        _loadPool(poolId);
        _setupRepresentingConvexTokenClone();

        vm.expectRevert(ErrorLib.InvalidInput.selector);
        bridge.convert(
            AztecTypes.AztecAsset(1, invalidCurveLpToken, AztecTypes.AztecAssetType.VIRTUAL),
            emptyAsset,
            AztecTypes.AztecAsset(100, rctClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            depositAmount,
            0,
            0,
            BENEFICIARY
        );
    }

    function testInvalidInputAssetTypeEth(uint256 _poolId) public {
        uint256 depositAmount = 1e16;
        uint256 poolId = _getPoolId(_poolId);

        _setupBridge(poolId);
        _loadPool(poolId);
        _setupRepresentingConvexTokenClone();

        vm.expectRevert(ErrorLib.InvalidInput.selector);
        bridge.convert{value: depositAmount}(
            AztecTypes.AztecAsset(1, address(0), AztecTypes.AztecAssetType.ETH),
            emptyAsset,
            AztecTypes.AztecAsset(100, rctClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            depositAmount,
            0,
            0,
            BENEFICIARY
        );
    }

    function testInvalidOutput1(uint256 _poolId) public {
        uint256 depositAmount = 1e16;
        address invalidLpToken = address(123);
        uint256 poolId = _getPoolId(_poolId);

        _setupBridge(poolId);
        _loadPool(poolId);
        _setupRepresentingConvexTokenClone();

        // make deposit
        uint256 rctMinted = _deposit(depositAmount);

        vm.expectRevert(ErrorLib.InvalidInput.selector);
        bridge.convert(
            AztecTypes.AztecAsset(100, rctClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(1, invalidLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            rctMinted,
            0,
            0,
            BENEFICIARY
        );
    }

    // Curve LP token of another pool is tried to be withdrawn -> pool "Curve LP token - RCT" mismatch
    function testInvalidOutput2() public {
        uint256 depositAmount = 1e16;

        uint256 selectedPool = 25;
        uint256 anotherPoolId = 23;
        address incorrectCurveLpToken; // valid curve lp token of another already loaded pool

        _setupBridge(selectedPool);

        // both pools are loaded
        _loadPool(selectedPool);
        _loadPool(anotherPoolId);

        _setupRepresentingConvexTokenClone();

        // make deposit for a pool at index `lastPoolId`
        uint256 rctMinted = _deposit(depositAmount);

        // withdraw using incorrect pool - RCT Asset address won't match deployed RCT clone address of the provided Curve LP token
        (incorrectCurveLpToken,,,,,) = IConvexBooster(BOOSTER).poolInfo(anotherPoolId);
        vm.label(incorrectCurveLpToken, "Incorrect Curve LP Token Contract");

        vm.expectRevert(ErrorLib.InvalidInput.selector);
        bridge.convert(
            AztecTypes.AztecAsset(100, rctClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(1, incorrectCurveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            rctMinted,
            10,
            0,
            BENEFICIARY
        );
    }

    function testInvalidOutputEth(uint256 _poolId) public {
        uint256 depositAmount = 1e16;
        uint256 poolId = _getPoolId(_poolId);

        _setupBridge(poolId);
        _loadPool(poolId);
        _setupRepresentingConvexTokenClone();

        // make deposit, setup total balance in CurveRewards
        uint256 rctMinted = _deposit(depositAmount);

        vm.expectRevert(ErrorLib.InvalidInput.selector);
        bridge.convert(
            AztecTypes.AztecAsset(100, rctClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(20, address(0), AztecTypes.AztecAssetType.ETH),
            emptyAsset,
            rctMinted,
            10,
            0,
            BENEFICIARY
        );
    }

    function testConvertInvalidCaller(uint256 _poolId) public {
        address invalidCaller = address(123);
        uint256 depositAmount = 1e16;
        uint256 poolId = _getPoolId(_poolId);

        _setupBridge(poolId);
        _loadPool(poolId);
        _setupRepresentingConvexTokenClone();

        vm.prank(invalidCaller);
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(100, rctClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            depositAmount,
            0,
            0,
            BENEFICIARY
        );
    }

    function testLoadUnsupportedPool() public {
        _setupBridge(100);

        vm.expectRevert(abi.encodeWithSelector(UnsupportedPool.selector, 100));
        _loadPool(100);
    }

    function testInsufficientFirstDepositAmount(uint256 _poolId) public {
        uint256 depositAmount = 1e16 - 1;
        uint256 poolId = _getPoolId(_poolId);

        _setupBridge(poolId);
        _mockInitialRewardBalances(false);

        _loadPool(poolId);
        _setupRepresentingConvexTokenClone();
        _setupSubsidy();

        vm.expectRevert(InsufficientFirstDepositAmount.selector);
        bridge.convert(
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(100, rctClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            depositAmount,
            0,
            0,
            BENEFICIARY
        );
    }

    function testLoadSamePoolTwice(uint256 _poolId) public {
        uint256 poolId = _getPoolId(_poolId);
        _setupBridge(poolId);

        _loadPool(poolId);

        vm.expectRevert(abi.encodeWithSelector(PoolAlreadyLoaded.selector, poolId));
        _loadPool(poolId);
    }

    // pool not loaded yet, RCT not deployed yet
    function testPoolNotLoadedYet(uint256 _poolId) public {
        uint96 depositAmount = 1e16;

        uint256 poolId = _getPoolId(_poolId);

        _setupBridge(poolId);
        _setupRepresentingConvexTokenClone();

        // Mock initial balance of CURVE LP Token for Rollup Processor
        deal(curveLpToken, rollupProcessor, depositAmount);
        // transfer CURVE LP Tokens from RollUpProcessor to the bridge
        IERC20(curveLpToken).transfer(address(bridge), depositAmount);

        vm.expectRevert(bytes(""));
        bridge.convert(
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(100, rctClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            depositAmount,
            0,
            0,
            BENEFICIARY
        );
    }

    function testSingleDeposit(uint96 _depositAmount) public {
        vm.assume(_depositAmount > 1e16);

        for (uint256 i = 0; i < supportedPids.length; i++) {
            uint256 poolId = supportedPids[i];

            _setupBridge(poolId);
            _mockInitialRewardBalances(false);

            _loadPool(poolId);
            _setupRepresentingConvexTokenClone();
            _setupSubsidy();

            _deposit(_depositAmount);
            rewind(5 days);

            SUBSIDY.withdraw(BENEFICIARY);
            assertGt(BENEFICIARY.balance, 0, "Claimable subsidy amount was 0");
        }
    }

    function testSingleDepositSingleWithdrawal(uint96 _depositAmount) public {
        vm.assume(_depositAmount > 1e16);
        uint256 withdrawalAmount = uint256(_depositAmount) * uint256(4) / uint256(10);

        for (uint256 i = 0; i < supportedPids.length; i++) {
            uint256 poolId = supportedPids[i];

            _setupBridge(poolId);
            _mockInitialRewardBalances(false);

            _loadPool(poolId);
            _setupRepresentingConvexTokenClone();
            _setupSubsidy();

            _deposit(_depositAmount);
            _withdraw(withdrawalAmount);
            rewind(5 days);

            SUBSIDY.withdraw(BENEFICIARY);
            assertGt(BENEFICIARY.balance, 0, "Claimable subsidy amount was 0");
        }
    }

    function testSingleDepositDoubleWithdrawal() public {
        uint256 depositAmount1 = 1e39;
        uint256 withdrawalAmount1 = 1e30;
        uint256 withdrawalAmount2 = 1e10;

        for (uint256 i = 0; i < supportedPids.length; i++) {
            uint256 poolId = supportedPids[i];

            _setupBridge(poolId);
            _mockInitialRewardBalances(true);

            _loadPool(poolId);
            _setupRepresentingConvexTokenClone();
            _setupSubsidy();

            _deposit(depositAmount1);
            _withdraw(withdrawalAmount1);
            _withdraw(withdrawalAmount2);
            rewind(15 days);
        }
    }

    function testAlternatingDepositAndWithdrawal() public {
        uint256 depositAmount1 = 1e39;
        uint256 depositAmount2 = 1e10;
        uint256 withdrawalAmount1 = 1e30;
        uint256 withdrawalAmount2 = 1e10;

        for (uint256 i = 0; i < supportedPids.length; i++) {
            uint256 poolId = supportedPids[i];

            _setupBridge(poolId);
            _mockInitialRewardBalances(true);

            _loadPool(poolId);
            _setupRepresentingConvexTokenClone();
            _setupSubsidy();

            _deposit(depositAmount1);
            _withdraw(withdrawalAmount1);
            _deposit(depositAmount2);
            _withdraw(withdrawalAmount2);
            rewind(20 days);
        }
    }

    function testDoubleDepositDoubleWithdrawal() public {
        uint256 depositAmount1 = 1e39;
        uint256 depositAmount2 = 1e10;
        uint256 withdrawalAmount1 = 1e30;
        uint256 withdrawalAmount2 = 1e10;

        for (uint256 i = 0; i < supportedPids.length; i++) {
            uint256 poolId = supportedPids[i];

            _setupBridge(poolId);
            _mockInitialRewardBalances(true);

            _loadPool(poolId);
            _setupRepresentingConvexTokenClone();
            _setupSubsidy();

            // deposit Curve LP tokens, set up totalSupply on CurveRewards
            _deposit(depositAmount1);
            _deposit(depositAmount2);

            _withdraw(withdrawalAmount1);
            _withdraw(withdrawalAmount2);
            rewind(20 days);
        }
    }

    function testSwapNotEnoughRewards(uint96 _depositAmount, uint256 _poolId) public {
        vm.assume(_depositAmount > 1e16);

        uint256 poolId = _getPoolId(_poolId);

        _setupBridge(poolId);
        _mockInitialRewardBalances(false);

        _loadPool(poolId);
        _setupRepresentingConvexTokenClone();
        _setupSubsidy();

        // fake reward balances - set low enough to prevent swap
        vm.mockCall(CRV, abi.encodeWithSelector(IERC20(CRV).balanceOf.selector, address(bridge)), abi.encode(0));
        vm.mockCall(CVX, abi.encodeWithSelector(IERC20(CVX).balanceOf.selector, address(bridge)), abi.encode(0));

        _deposit(_depositAmount);
        _withdraw(_depositAmount);
        rewind(10 days);

        vm.clearMockedCalls();
    }

    function testWithdrawalWhenPoolShutdown(uint256 _poolId) public {
        uint256 depositAmount = 1e24;
        uint256 withdrawalAmount = 1e10;

        uint256 poolId = _getPoolId(_poolId);

        _setupBridge(poolId);
        _mockInitialRewardBalances(false);

        _loadPool(poolId);
        _setupRepresentingConvexTokenClone();
        _setupSubsidy();

        _deposit(depositAmount);

        // shut down pool
        vm.startPrank(BOOSTER_POOL_MANAGER);
        bool isPoolShutdown = IConvexBooster(BOOSTER).shutdownPool(poolId);
        vm.stopPrank();

        assertTrue(isPoolShutdown);

        _withdraw(withdrawalAmount);
    }

    function testAttackResistanceFirstDeposits() public {
        // Has to be greater than 1e2 (attackAmount / 1e10 / RCT token supply) (1e28 / 1e10 / 1e16) for the inflation resistance mechanism to work
        uint256 userDeposit = 1e2 + 1;

        _attackResistanceFirstDeposits(userDeposit);
    }

    /** 
     * @dev Earning is negligable so this kind of attack is unlikely. The whole attack would be likely unsuccessful as anyone depositing a regular amount would thwart the attack causing the attacker to lose significant portion of their tokens.
    */
    function testFailAttackResistanceFirstDeposits() public {
        // Deposit is not greater than 1e2 -> inflation protection mechanism fails -> exploit will succeed
        uint256 userDeposit = 1e2;

        _attackResistanceFirstDeposits(userDeposit);
    }

    function testAttackResistanceRatioResetProtection() public {
        uint256 anotherUsersDeposit = 1e18; // has to be greater than 1e18 (in this case) (attackAmount / 1e10 / RCTTotalAmount) ~ (1e28 / 1e10 / ~1), otherwise exploit will be successful
        
        _attackResistanceRatioResetProtection(anotherUsersDeposit);
    }

    /** 
    * @dev Exploit of generally smaller deposits possible. Still very risky for the attacker, as soon as a regular amount is deposited, attacker will lose significant portion of his tokens.
    */
    function testFailAttackResistanceRatioResetProtection() public {
        uint256 anotherUsersDeposit = 1e17; // if deposit less than ca. 1e16 (in this case) (attackAmount / 1e10 / RCTTotalAmount) ~ (1e28 / 1e10 / ~1) -> inflation protection mechanism may fail -> exploit of smaller deposits possible
        
        _attackResistanceRatioResetProtection(anotherUsersDeposit);
    }

    /**
     * @notice Performs deposit of Curve LP tokens and checks.
     * @dev Mocking of Curve LP token balance.
     * @dev Transferring minted RCT tokens to RollupProcessor
     * @param _depositAmount Number of Curve LP tokens to stake.
     * @return outputValueA Number of minted RCT
     */
    function _deposit(uint256 _depositAmount) internal returns (uint256) {
        // Mock initial balance of CURVE LP Token for Rollup Processor
        deal(curveLpToken, rollupProcessor, _depositAmount);

        // transfer CURVE LP Tokens from RollUpProcessor to the bridge
        IERC20(curveLpToken).transfer(address(bridge), _depositAmount);

        uint256 startRctAmt = IERC20(rctClone).balanceOf(rollupProcessor);

        skip(5 days); // accumulate rewards and subsidy
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(100, rctClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            _depositAmount,
            0,
            0,
            BENEFICIARY
        );

        uint256 totalSupplyRCTBeforeMintingNew = IRepConvexToken(rctClone).totalSupply() - outputValueA;
        uint256 curveLpTokensBeforeDepositing = ICurveRewards(curveRewards).balanceOf(address(bridge))
            - IERC20(curveLpToken).balanceOf(address(bridge)) - _depositAmount;

        if (totalSupplyRCTBeforeMintingNew == 0) {
            assertEq(outputValueA, InflationProtection._toShares(_depositAmount, 0, 0, true), "RCT amt not equal to Curve LP");
        } else {
            assertEq(
                outputValueA,
                InflationProtection._toShares(_depositAmount, totalSupplyRCTBeforeMintingNew, curveLpTokensBeforeDepositing, false),
                "RCT amount does not match"
            );
        }
        assertEq(outputValueB, 0, "Output value B is not 0.");
        assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");

        // check balance of minted rep convex tokens
        assertEq(IERC20(rctClone).balanceOf(address(bridge)), outputValueA);

        // transfer representing Convex token to RollupProcessor
        IERC20(rctClone).transferFrom(address(bridge), rollupProcessor, outputValueA);
        assertEq(IERC20(rctClone).balanceOf(rollupProcessor), startRctAmt + outputValueA);

        return outputValueA;
    }

    /**
     * @notice Performs withdrawal of Curve LP tokens and asserts.
     * @dev Transferring RCT tokens to the bridge and unstaked Curve LP tokens back to Rollup
     * @dev Checks of unstaked Curve LP tokens, earned rewards and claimed subsidy.
     * @param _withdrawalAmount Number of RCT tokens to exchange for Curve LP tokens
     */
    function _withdraw(uint256 _withdrawalAmount) internal returns (uint256) {
        // transfer representing Convex tokens to the bridge
        uint256 startCurveLpTokenAmt = IERC20(curveLpToken).balanceOf(rollupProcessor);
        uint256 startRctAmt = IERC20(rctClone).balanceOf(rollupProcessor);
        IERC20(rctClone).transfer(address(bridge), _withdrawalAmount);

        uint256 totalSupplyRCTBeforeBurning = IRepConvexToken(rctClone).totalSupply();

        skip(5 days); // accumulate rewards and subsidy
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
            AztecTypes.AztecAsset(100, rctClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            _withdrawalAmount,
            10,
            0,
            BENEFICIARY
        );

        assertEq(outputValueB, 0, "Output value B is greater than 0");
        assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");

        // Transfer Curve LP tokens from the bridge to Rollup Processor
        IERC20(curveLpToken).transferFrom(address(bridge), rollupProcessor, outputValueA);
        assertEq(IERC20(curveLpToken).balanceOf(rollupProcessor), startCurveLpTokenAmt + outputValueA);

        uint256 unstakedRewardLpTokensAfter = IERC20(curveLpToken).balanceOf(address(bridge));
        uint256 stakedCurveLpTokensEnd = ICurveRewards(curveRewards).balanceOf(address(bridge));
        uint256 curveLpTokenAmt = InflationProtection._toAmount(_withdrawalAmount, totalSupplyRCTBeforeBurning, stakedCurveLpTokensEnd + unstakedRewardLpTokensAfter + outputValueA, false);

        assertEq(outputValueA, curveLpTokenAmt);

        // // Check that representing Convex tokens were successfully burned
        assertEq(IERC20(rctClone).balanceOf(rollupProcessor), startRctAmt - _withdrawalAmount);

        // Claim subsidy at withdrawal
        SUBSIDY.withdraw(BENEFICIARY);
        assertGt(BENEFICIARY.balance, 0, "Claimable subsidy amount was 0");

        return outputValueA;
    }

    function _attackResistanceFirstDeposits(uint256 _userDeposit) internal {
        // uint256 poolId = _getPoolId(_poolId);
        
        // Miminal initial deposit
        uint256 minInitDeposit = 1e16;

        address attacker = address(666);
        uint256 attackAmount = 1e28;

        for (uint256 i = 0; i < supportedPids.length; i++) {
            uint256 poolId = supportedPids[i];

            _setupBridge(poolId);
            _mockInitialRewardBalances(false);

            _loadPool(poolId);
            _setupRepresentingConvexTokenClone();
            _setupSubsidy();
            
            // Attacker performs first deposit
            uint256 rctMintedForAttacker = _deposit(minInitDeposit);

            // Attack
            _airdropAttack(poolId, attacker, attackAmount);

            // Regular user
            uint256 rctMinted = _deposit(_userDeposit);

            // Inflation protection mechanism ensures that user will not lose his deposit due to inflation attack -> non-zero value
            assertGt(rctMinted, 0);

            uint256 stakedCurveLpTokenBeforeWithdrawal = IERC20(curveRewards).balanceOf(address(bridge));

            // Attacker withdraws their initial deposit
            uint256 retrievedCurveLp = _withdraw(rctMintedForAttacker);

            rewind(15 days);

            // Attacker is unable to steal all the funds
            assertLt(retrievedCurveLp, stakedCurveLpTokenBeforeWithdrawal);
        }
    }

    function _attackResistanceRatioResetProtection(uint256 _anotherUsersDeposit) internal {
        uint256 minInitDeposit = 1e16;

        address attacker = address(666);
        uint256 attackerMinDeposit = 1;
        uint256 attackAmount = 1e28;

        for (uint256 i = 0; i < supportedPids.length; i++) {
            uint256 poolId = supportedPids[i];

            _setupBridge(poolId);
            _mockInitialRewardBalances(false);

            _loadPool(poolId);
            _setupRepresentingConvexTokenClone();
            _setupSubsidy();
            
            // Regular user performs first deposit
            uint256 rctMinted = _deposit(minInitDeposit);

            // Same user withdraws almost all of his funds, effectivelly resetting inflation ratio and exposing contract to inflation attack again
            _withdraw(rctMinted - 1);

            // Attacker notices it and performs a deposit
            uint256 rctMintedForAttacker = _deposit(attackerMinDeposit);

            // Attack
            _airdropAttack(poolId, attacker, attackAmount);

            // Another regular user
            uint256 rctMintedAnotherUser = _deposit(_anotherUsersDeposit);

            // Inflation protection mechanism ensures that user will not lose his deposit due to inflation attack -> non-zero value
            assertGt(rctMintedAnotherUser, 0);

            uint256 stakedCurveLpTokenBeforeWithdrawal = IERC20(curveRewards).balanceOf(address(bridge));

            // Attacker withdraws their initial deposit
            uint256 attackerRetrievedCurveLp = _withdraw(rctMintedForAttacker);

            // another user withdraws their deposit
            uint256 userRetrievedCurveLp = _withdraw(rctMintedAnotherUser);

            // Attacker is unable to steal all the funds
            assertLt(attackerRetrievedCurveLp, stakedCurveLpTokenBeforeWithdrawal);

            // Other user is didn't lose access to his deposit
            assertGt(userRetrievedCurveLp, 0);

            rewind(30 days);
        }
    }

    function _airdropAttack(uint256 _poolId, address _attacker, uint256 _attackAmount) internal {
        vm.startPrank(_attacker);
        deal(curveLpToken, _attacker, _attackAmount);
        IERC20(curveLpToken).approve(BOOSTER, _attackAmount);
        IConvexBooster(BOOSTER).deposit(_poolId, _attackAmount, false);
        uint256 balance = IERC20(convexLpToken).balanceOf(_attacker);
        IERC20(convexLpToken).approve(curveRewards, type(uint256).max);
        ICurveRewards(curveRewards).stakeFor(address(bridge), balance);
        vm.stopPrank();
    }

    function _setupRepresentingConvexTokenClone() internal {
        rctImplementation = bridge.RCT_IMPLEMENTATION();
        vm.label(rctImplementation, "Representing Convex Token Implementation");

        rctClone = bridge.deployedClones(curveLpToken);
        vm.label(rctClone, "Representing Convex Token Clone");
    }

    function _loadPool(uint256 _poolId) internal {
        bridge.loadPool(_poolId);
    }

    function _setupBridge(uint256 _poolId) internal {
        bridge = new ConvexStakingBridge(rollupProcessor);
        (curveLpToken, convexLpToken, gauge, curveRewards, stash,) = IConvexBooster(BOOSTER).poolInfo(_poolId);

        // labels
        vm.label(address(bridge), "Bridge");
        vm.label(curveLpToken, "Curve LP Token Contract");
        vm.label(convexLpToken, "Convex LP Token Contract");
        vm.label(curveRewards, "Curve Rewards Contract");
        vm.label(stash, "Stash Contract");
        vm.label(gauge, "Gauge Contract");
    }

    /**
     * @dev Sets reward balances which will force rewards to be exchanged, if set to true
     * @dev These balances are not taken into consideration by the curveRewards contract which affects the calculation of outputValueA and may prevent withdrawing of all deposited funds
     */
    function _mockInitialRewardBalances(bool _isMockActive) internal {
        if (_isMockActive) {
            deal(CRV, address(bridge), 3e22);
            deal(CVX, address(bridge), 3e22);
        }
    }

    function _setupSubsidy() internal {
        // Set ETH balance of bridge and BENEFICIARY to 0 for clarity (somebody sent ETH to that address on mainnet)
        vm.deal(address(bridge), 0);
        vm.deal(BENEFICIARY, 0);

        uint256[] memory criterias = new uint256[](2);

        criterias[0] = bridge.computeCriteria(
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(100, rctClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            0
        );

        criterias[1] = bridge.computeCriteria(
            AztecTypes.AztecAsset(100, rctClone, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            AztecTypes.AztecAsset(1, curveLpToken, AztecTypes.AztecAssetType.ERC20),
            emptyAsset,
            0
        );

        uint32 minGasPerMinute = 700;

        SUBSIDY.subsidize{value: 1 ether}(address(bridge), criterias[0], minGasPerMinute);
        SUBSIDY.subsidize{value: 1 ether}(address(bridge), criterias[1], minGasPerMinute);

        SUBSIDY.registerBeneficiary(BENEFICIARY);
    }

    function _getPoolId(uint256 _poolId) internal view returns (uint256 poolId) {
        // select a pool from a given range
        poolId = supportedPids[bound(_poolId, 0, 9)];
    }
}
