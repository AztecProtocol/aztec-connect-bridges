// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {ConvexStakingBridge} from "../../../bridges/convex/ConvexStakingBridge.sol";
import {IConvexBooster} from "../../../interfaces/convex/IConvexBooster.sol";
import {ICurveRewards} from "../../../interfaces/convex/ICurveRewards.sol";
import {IRepConvexToken} from "../../../interfaces/convex/IRepConvexToken.sol";
import {InflationProtection} from "../../../libraries/convex/InflationProtection.sol";

contract ConvexStakingBridgeE2ETest is BridgeTestBase {
    address private constant BOOSTER = 0xF403C135812408BFbE8713b5A23a04b3D48AAE31;
    address private constant BENEFICIARY = address(777);
    address private constant CRV = 0xD533a949740bb3306d119CC777fa900bA034cd52;
    address private constant CVX = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;

    address private curveLpToken;
    address private convexLpToken;
    address private representingConvexToken;
    address private rctImplementation;
    address private rctClone;
    address private staker;
    address private gauge;
    address private stash;
    address private curveRewards;
    // The reference to the convex staking bridge
    ConvexStakingBridge private bridge;

    uint256[10] public supportedPids = [23, 25, 32, 33, 38, 40, 49, 61, 64, 122];

    function setUp() public {
        staker = IConvexBooster(BOOSTER).staker();

        // labels
        vm.label(address(ROLLUP_PROCESSOR), "Rollup Processor");
        vm.label(address(this), "E2E Test Contract");
        vm.label(msg.sender, "MSG sender");
        vm.label(BOOSTER, "Booster");
        vm.label(staker, "Staker Contract Address");
        vm.label(BENEFICIARY, "Beneficiary");
        vm.label(rctClone, "RCT");

        vm.label(CRV, "CRV token");
        vm.label(CVX, "CVX token");
    }

    function testSingleDepositSingleWithdrawalFlow(uint96 _depositAmount) public {
        vm.assume(_depositAmount > 1e16);

        for (uint256 i = 0; i < supportedPids.length; i++) {
            uint256 poolId = supportedPids[i];

            _setupBridge(poolId);
            _mockInitialRewardBalances(false);

            _loadPool(poolId);
            _setupRepresentingConvexTokenClone();
            _setupSubsidy();

            vm.startPrank(MULTI_SIG);
            // Add the new bridge twice - once for deposit, once for withdrawal - and set their initial gasLimits
            ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 3500000); // deposits
            ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 2500000); // withdrawals
            // Add assets and set their initial gasLimits
            ROLLUP_PROCESSOR.setSupportedAsset(curveLpToken, 100000);
            ROLLUP_PROCESSOR.setSupportedAsset(rctClone, 100000);
            vm.stopPrank();

            // Fetch the ids of the Convex Staking bridge
            uint256 depositBridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength() - 1;
            uint256 withdrawalBridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength();

            // get Aztec assets
            AztecTypes.AztecAsset memory curveLpAsset = ROLLUP_ENCODER.getRealAztecAsset(curveLpToken);
            AztecTypes.AztecAsset memory representingConvexAsset = ROLLUP_ENCODER.getRealAztecAsset(rctClone);

            _deposit(depositBridgeId, curveLpAsset, representingConvexAsset, _depositAmount);
            _withdraw(
                withdrawalBridgeId, representingConvexAsset, curveLpAsset, _depositAmount * uint256(6) / uint256(10)
            );

            rewind(10 days);
        }
    }

    function testAlternatingDepositWithdrawalFlow(uint96 _depositAmount) public {
        vm.assume(_depositAmount > 1e16);

        for (uint256 i = 0; i < supportedPids.length; i++) {
            uint256 poolId = supportedPids[i];

            _setupBridge(poolId);
            _mockInitialRewardBalances(false);

            _loadPool(poolId);
            _setupRepresentingConvexTokenClone();
            _setupSubsidy();

            vm.startPrank(MULTI_SIG);
            // Add the new bridge twice - once for deposit, once for withdrawal - and set their initial gasLimits
            ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 3500000); // deposits
            ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 2500000); // withdrawals
            // Add assets and set their initial gasLimits
            ROLLUP_PROCESSOR.setSupportedAsset(curveLpToken, 100000);
            ROLLUP_PROCESSOR.setSupportedAsset(rctClone, 100000);
            vm.stopPrank();

            // Fetch the ids of the Convex Staking bridge
            uint256 depositBridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength() - 1;
            uint256 withdrawalBridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength();

            // get Aztec assets
            AztecTypes.AztecAsset memory curveLpAsset = ROLLUP_ENCODER.getRealAztecAsset(curveLpToken);
            AztecTypes.AztecAsset memory representingConvexAsset = ROLLUP_ENCODER.getRealAztecAsset(rctClone);

            // // Mint depositAmount of Curve LP tokens for RollUp Processor
            _deposit(depositBridgeId, curveLpAsset, representingConvexAsset, _depositAmount);
            _withdraw(
                withdrawalBridgeId, representingConvexAsset, curveLpAsset, _depositAmount * uint256(6) / uint256(10)
            );
            _deposit(depositBridgeId, curveLpAsset, representingConvexAsset, _depositAmount);
            _withdraw(
                withdrawalBridgeId, representingConvexAsset, curveLpAsset, _depositAmount * uint256(6) / uint256(10)
            );

            rewind(20 days);
        }
    }

    function testDoubleDepositDoubleWithdrawalFlow(uint96 _depositAmount) public {
        vm.assume(_depositAmount > 1e16);

        for (uint256 i = 0; i < supportedPids.length; i++) {
            uint256 poolId = supportedPids[i];

            _setupBridge(poolId);
            _mockInitialRewardBalances(false);

            _loadPool(poolId);
            _setupRepresentingConvexTokenClone();
            _setupSubsidy();

            vm.startPrank(MULTI_SIG);
            // Add the new bridge twice - once for deposit, once for withdrawal - and set their initial gasLimits
            ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 3500000); // deposits
            ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 2500000); // withdrawals
            // Add assets and set their initial gasLimits
            ROLLUP_PROCESSOR.setSupportedAsset(curveLpToken, 100000);
            ROLLUP_PROCESSOR.setSupportedAsset(rctClone, 100000);
            vm.stopPrank();

            // Fetch the ids of the Convex Staking bridge
            uint256 depositBridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength() - 1;
            uint256 withdrawalBridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength();

            // get Aztec assets
            AztecTypes.AztecAsset memory curveLpAsset = ROLLUP_ENCODER.getRealAztecAsset(curveLpToken);
            AztecTypes.AztecAsset memory representingConvexAsset = ROLLUP_ENCODER.getRealAztecAsset(rctClone);

            // // Mint depositAmount of Curve LP tokens for RollUp Processor

            _deposit(depositBridgeId, curveLpAsset, representingConvexAsset, _depositAmount);
            _deposit(depositBridgeId, curveLpAsset, representingConvexAsset, _depositAmount);

            _withdraw(
                withdrawalBridgeId, representingConvexAsset, curveLpAsset, _depositAmount * uint256(6) / uint256(10)
            );
            _withdraw(
                withdrawalBridgeId, representingConvexAsset, curveLpAsset, _depositAmount * uint256(6) / uint256(10)
            );

            rewind(20 days);
        }
    }

    function testDoubleDepositDoubleWithdrawalRewardsExchangedFlow() public {
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

            vm.startPrank(MULTI_SIG);
            // Add the new bridge twice - once for deposit, once for withdrawal - and set their initial gasLimits
            ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 3500000); // deposits
            ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 2500000); // withdrawals
            // Add assets and set their initial gasLimits
            ROLLUP_PROCESSOR.setSupportedAsset(curveLpToken, 100000);
            ROLLUP_PROCESSOR.setSupportedAsset(rctClone, 100000);
            vm.stopPrank();

            // Fetch the ids of the Convex Staking bridge
            uint256 depositBridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength() - 1;
            uint256 withdrawalBridgeId = ROLLUP_PROCESSOR.getSupportedBridgesLength();

            // get Aztec assets
            AztecTypes.AztecAsset memory curveLpAsset = ROLLUP_ENCODER.getRealAztecAsset(curveLpToken);
            AztecTypes.AztecAsset memory representingConvexAsset = ROLLUP_ENCODER.getRealAztecAsset(rctClone);

            _deposit(depositBridgeId, curveLpAsset, representingConvexAsset, depositAmount1);
            _deposit(depositBridgeId, curveLpAsset, representingConvexAsset, depositAmount2);

            _withdraw(withdrawalBridgeId, representingConvexAsset, curveLpAsset, withdrawalAmount1);
            _withdraw(withdrawalBridgeId, representingConvexAsset, curveLpAsset, withdrawalAmount2);

            rewind(20 days);
        }
    }

    function _deposit(
        uint256 _bridgeId,
        AztecTypes.AztecAsset memory _curveLpAsset,
        AztecTypes.AztecAsset memory _representingConvexAsset,
        uint256 _depositAmount
    ) internal returns (uint256) {
        uint256 startRctAmt = IERC20(rctClone).balanceOf(address(ROLLUP_PROCESSOR));

        // Mint depositAmount of Curve LP tokens for RollUp Processor
        deal(curveLpToken, address(ROLLUP_PROCESSOR), _depositAmount);

        ROLLUP_ENCODER.defiInteractionL2(
            _bridgeId, _curveLpAsset, emptyAsset, _representingConvexAsset, emptyAsset, 0, _depositAmount
        );

        skip(5 days); // accumulate rewards and subsidy
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        uint256 totalSupplyRCTBeforeMintingNew = IRepConvexToken(rctClone).totalSupply() - outputValueA;
        uint256 curveLpTokensBeforeDepositing = ICurveRewards(curveRewards).balanceOf(address(bridge))
            - IERC20(curveLpToken).balanceOf(address(bridge)) - _depositAmount; // this also includes staked rewards
        if (totalSupplyRCTBeforeMintingNew == 0) {
            assertEq(
                outputValueA,
                InflationProtection._convertToShares(_depositAmount, 0, 0),
                "RCT amt not equal to Curve LP"
            );
        } else {
            assertEq(
                outputValueA,
                InflationProtection._convertToShares(
                    _depositAmount, totalSupplyRCTBeforeMintingNew, curveLpTokensBeforeDepositing
                ),
                "RCT amount does not match"
            );
        }

        assertEq(outputValueB, 0, "Output value B is not 0");
        assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");
        assertEq(IERC20(rctClone).balanceOf(address(ROLLUP_PROCESSOR)), startRctAmt + outputValueA);
        assertGt(SUBSIDY.claimableAmount(BENEFICIARY), 0, "Claimable subsidy amount was 0");
        return outputValueA;
    }

    function _withdraw(
        uint256 _bridgeId,
        AztecTypes.AztecAsset memory _representingConvexAsset,
        AztecTypes.AztecAsset memory _curveLpAsset,
        uint256 _withdrawalAmount
    ) internal {
        uint256 startRctAmt = IERC20(rctClone).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 curveLpBalanceOfRollupBefore = IERC20(curveLpToken).balanceOf(address(ROLLUP_PROCESSOR));
        // Compute withdrawal calldata
        ROLLUP_ENCODER.defiInteractionL2(
            _bridgeId, _representingConvexAsset, emptyAsset, _curveLpAsset, emptyAsset, 0, _withdrawalAmount
        );

        skip(5 days); // accumulate rewards and subsidy
        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = ROLLUP_ENCODER.processRollupAndGetBridgeResult();

        uint256 stakedCurveLpTokensEnd = ICurveRewards(curveRewards).balanceOf(address(bridge));
        uint256 unstakedRewardLpTokensAfter = IERC20(curveLpToken).balanceOf(address(bridge));
        uint256 totalSupplyRCTBeforeBurning = IRepConvexToken(rctClone).totalSupply() + _withdrawalAmount;

        uint256 curveLpTokenAmt = InflationProtection._convertToAssets(
            _withdrawalAmount,
            totalSupplyRCTBeforeBurning,
            stakedCurveLpTokensEnd + unstakedRewardLpTokensAfter + outputValueA
        );

        assertEq(outputValueA, curveLpTokenAmt, "Curve LP amount does not match");
        assertEq(outputValueB, 0, "Output value B is greater than 0");
        assertTrue(!isAsync, "Bridge is in async mode which it shouldn't");

        assertEq(IERC20(curveLpToken).balanceOf(address(ROLLUP_PROCESSOR)), curveLpBalanceOfRollupBefore + outputValueA); // Curve LP tokens owned by RollUp after withdrawal

        assertEq(IERC20(rctClone).balanceOf(address(ROLLUP_PROCESSOR)), startRctAmt - _withdrawalAmount); // RCT succesfully burned
        assertGt(SUBSIDY.claimableAmount(BENEFICIARY), 0, "Claimable subsidy amount was 0");
    }

    function _setupSubsidy() internal {
        // sets ETH balance of bridge and BENEFICIARY to 0
        vm.deal(address(bridge), 0);
        vm.deal(BENEFICIARY, 0);

        uint256[] memory criterias = new uint256[](2);

        // different criteria for deposit and withdrawal
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

        // Set the rollupBeneficiary on BridgeTestBase so that it gets included in the proofData
        ROLLUP_ENCODER.setRollupBeneficiary(BENEFICIARY);
    }

    function _setupBridge(uint256 _poolId) internal {
        bridge = new ConvexStakingBridge(address(ROLLUP_PROCESSOR));
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
     * @dev Sets reward balances high enough to guarantee that rewards are going to be exchanged
     * @dev These balances are not taken into consideration by the curveRewards contract which prevents withdrawing of all deposited funds
     */
    function _mockInitialRewardBalances(bool _isMockActive) internal {
        if (_isMockActive) {
            deal(CRV, address(bridge), 3e22);
            deal(CVX, address(bridge), 3e22);
        }
    }

    function _loadPool(uint256 _poolId) internal {
        bridge.loadPool(_poolId);
    }

    function _setupRepresentingConvexTokenClone() internal {
        rctImplementation = bridge.RCT_IMPLEMENTATION();
        vm.label(rctImplementation, "Representing Convex Token Implementation");

        rctClone = bridge.deployedClones(curveLpToken);
        vm.label(rctClone, "Representing Convex Token Clone");
    }
}
