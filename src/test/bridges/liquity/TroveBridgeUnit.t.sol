// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {TroveBridge} from "../../../bridges/liquity/TroveBridge.sol";
import {TroveBridgeTestBase} from "./TroveBridgeTestBase.sol";

contract TroveBridgeUnitTest is TroveBridgeTestBase {
    AztecTypes.AztecAsset internal emptyAsset;

    function setUp() public {
        rollupProcessor = address(this);

        vm.prank(OWNER);
        bridge = new TroveBridge(rollupProcessor, 160);

        _baseSetUp();
    }

    function testInitialERC20Params() public {
        assertEq(bridge.name(), "TroveBridge");
        assertEq(bridge.symbol(), "TB-160");
        assertEq(uint256(bridge.decimals()), 18);
    }

    function testInvalidTroveStatus() public {
        // Attempt borrowing when trove was not opened - state 0
        vm.deal(rollupProcessor, ROLLUP_PROCESSOR_ETH_BALANCE);
        vm.expectRevert(abi.encodeWithSignature("InvalidStatus(uint8,uint8,uint8)", 1, 1, 0));
        bridge.convert(
            AztecTypes.AztecAsset(3, address(0), AztecTypes.AztecAssetType.ETH),
            emptyAsset,
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            ROLLUP_PROCESSOR_ETH_BALANCE,
            0,
            MAX_FEE,
            address(0)
        );
    }

    function testInvalidInput() public {
        // Call convert with invalid input
        vm.expectRevert(ErrorLib.InvalidInput.selector);
        bridge.convert(
            emptyAsset,
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            emptyAsset,
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            0,
            0,
            0,
            address(0)
        );
    }

    function testFullFlow() public {
        // This is the only way how to make 1 part of test depend on another in DSTest because tests are otherwise ran
        // in parallel in different EVM instances. For this reason these parts of tests can't be evaluated individually
        // unless ran repeatedly.
        _openTrove();
        _borrow(ROLLUP_PROCESSOR_ETH_BALANCE);
        _repay(ROLLUP_PROCESSOR_ETH_BALANCE, 1, false, 1);
        _closeTrove();

        // Try reopening the trove
        deal(tokens["LUSD"].addr, OWNER, 0); // delete user's LUSD balance to make accounting easier in _openTrove(...)
        _openTrove();
    }

    function testLiquidationFlow() public {
        _openTrove();
        _borrow(ROLLUP_PROCESSOR_ETH_BALANCE);

        // Drop price and liquidate the trove
        setLiquityPrice(LIQUITY_PRICE_FEED.fetchPrice() / 2);
        TROVE_MANAGER.liquidate(address(bridge));
        Status troveStatus = Status(TROVE_MANAGER.getTroveStatus(address(bridge)));
        assertTrue(troveStatus == Status.closedByLiquidation, "Invalid trove status");

        // Set msg.sender to OWNER
        vm.startPrank(OWNER);

        // Bridge is now defunct so check that closing and reopening fails with appropriate errors
        vm.expectRevert(TroveBridge.OwnerNotLast.selector);
        bridge.closeTrove();

        vm.expectRevert(TroveBridge.NonZeroTotalSupply.selector);
        bridge.openTrove(address(0), address(0), MAX_FEE);

        vm.stopPrank();
    }

    function testLiquidationFlowWithCollateralToClaim() public {
        uint256 currentPrice = LIQUITY_PRICE_FEED.fetchPrice();
        uint256 totalCollateralRatio = TROVE_MANAGER.getTCR(currentPrice);
        uint256 targetCollateralRatio = 1300000000000000000;

        vm.prank(OWNER);
        bridge = new TroveBridge(rollupProcessor, totalCollateralRatio / 1e16);

        _openTrove();
        _borrow(ROLLUP_PROCESSOR_ETH_BALANCE);

        uint256 targetPrice = (currentPrice * targetCollateralRatio) / totalCollateralRatio;
        setLiquityPrice(targetPrice);
        assertTrue(TROVE_MANAGER.checkRecoveryMode(targetPrice), "Liquity not in recovery mode");

        uint256 icr = TROVE_MANAGER.getCurrentICR(address(bridge), targetPrice);
        assertGt(icr, MCR, "Trove's ICR lower than MCR");
        assertLt(icr, CCR, "Trove's ICR bigger than CCR");

        TROVE_MANAGER.liquidate(address(bridge));

        _redeem();

        // Close the trove
        uint256 ownerEthBalanceBefore = OWNER.balance;
        vm.prank(OWNER);
        bridge.closeTrove();
        uint256 ownerEthBalanceAfter = OWNER.balance;
        assertGt(
            ownerEthBalanceAfter,
            ownerEthBalanceBefore,
            "Owner's ETH balance didn't rise after closing the trove"
        );

        // Try reopening the trove
        deal(tokens["LUSD"].addr, OWNER, 0); // delete user's LUSD balance to make accounting easier in _openTrove(...)
        _openTrove();
    }

    function testRedeemFlow() public {
        vm.prank(OWNER);
        bridge = new TroveBridge(rollupProcessor, 110);

        _openTrove();
        _borrow(ROLLUP_PROCESSOR_ETH_BALANCE);

        address lowestIcrTrove = SORTED_TROVES.getLast();
        assertEq(lowestIcrTrove, address(bridge), "Bridge's trove is not the first one to redeem.");

        (uint256 debtBefore, , , ) = TROVE_MANAGER.getEntireDebtAndColl(address(bridge));

        uint256 amountToRedeem = debtBefore * 2;

        uint256 price = TROVE_MANAGER.priceFeed().fetchPrice();

        (, uint256 partialRedemptionHintNICR, ) = HINT_HELPERS.getRedemptionHints(amountToRedeem, price, 0);

        (address approxPartialRedemptionHint, , ) = HINT_HELPERS.getApproxHint(partialRedemptionHintNICR, 50, 42);

        (address exactUpperPartialRedemptionHint, address exactLowerPartialRedemptionHint) = SORTED_TROVES
            .findInsertPosition(partialRedemptionHintNICR, approxPartialRedemptionHint, approxPartialRedemptionHint);

        // Keep on redeeming 20 million LUSD until the trove is in the closedByRedemption status
        deal(tokens["LUSD"].addr, address(this), amountToRedeem);
        TROVE_MANAGER.redeemCollateral(
            amountToRedeem,
            lowestIcrTrove,
            exactUpperPartialRedemptionHint,
            exactLowerPartialRedemptionHint,
            partialRedemptionHintNICR,
            0,
            1e18
        );

        assertEq(TROVE_MANAGER.getTroveStatus(address(bridge)), 4, "Status is not closedByRedemption");

        _redeem();
        _closeRedeem();

        // Try reopening the trove
        deal(tokens["LUSD"].addr, OWNER, 0); // delete user's LUSD balance to make accounting easier in _openTrove(...)
        _openTrove();
    }

    function testPartialRedeemFlow() public {
        vm.prank(OWNER);
        bridge = new TroveBridge(rollupProcessor, 110);

        _openTrove();
        _borrow(60 ether);

        address lowestIcrTrove = SORTED_TROVES.getLast();
        assertEq(lowestIcrTrove, address(bridge), "Bridge's trove is not the first one to redeem.");

        (uint256 debtBefore, , , ) = TROVE_MANAGER.getEntireDebtAndColl(address(bridge));

        uint256 amountToRedeem = debtBefore / 2;

        uint256 price = TROVE_MANAGER.priceFeed().fetchPrice();

        (, uint256 partialRedemptionHintNICR, ) = HINT_HELPERS.getRedemptionHints(amountToRedeem, price, 0);

        (address approxPartialRedemptionHint, , ) = HINT_HELPERS.getApproxHint(partialRedemptionHintNICR, 50, 42);

        (address exactUpperPartialRedemptionHint, address exactLowerPartialRedemptionHint) = SORTED_TROVES
            .findInsertPosition(partialRedemptionHintNICR, approxPartialRedemptionHint, approxPartialRedemptionHint);

        deal(tokens["LUSD"].addr, address(this), amountToRedeem);
        TROVE_MANAGER.redeemCollateral(
            amountToRedeem,
            lowestIcrTrove,
            exactUpperPartialRedemptionHint,
            exactLowerPartialRedemptionHint,
            partialRedemptionHintNICR,
            0,
            1e18
        );

        // Check the trove was partially redeemed by checking that the trove's debt amount dropped but the trove
        // stayed active - not closed by redemption
        (uint256 debtAfterRedemption, , , ) = TROVE_MANAGER.getEntireDebtAndColl(address(bridge));
        assertEq(
            debtAfterRedemption,
            debtBefore - amountToRedeem,
            "Debt amount isn't equal to original debt - amount redeemed"
        );

        uint256 status = TROVE_MANAGER.getTroveStatus(address(bridge));
        assertEq(status, uint256(Status.active), "Status is not active");

        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset(
            2,
            address(bridge),
            AztecTypes.AztecAssetType.ERC20
        );
        AztecTypes.AztecAsset memory inputAssetB = AztecTypes.AztecAsset(
            1,
            tokens["LUSD"].addr,
            AztecTypes.AztecAssetType.ERC20
        );
        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset(3, address(0), AztecTypes.AztecAssetType.ETH);
        AztecTypes.AztecAsset memory outputAssetB = AztecTypes.AztecAsset(
            1,
            tokens["LUSD"].addr,
            AztecTypes.AztecAssetType.ERC20
        );

        // inputValue is equal to rollupProcessor's TroveBridge accounting token (TB) balance --> we want to repay
        // the debt in full
        uint256 inputValue = bridge.balanceOf(rollupProcessor);
        // Transfer TB to the bridge
        IERC20(inputAssetA.erc20Address).transfer(address(bridge), inputValue);

        // Mint the debt amount of LUSD to the bridge
        deal(inputAssetB.erc20Address, address(bridge), inputValue + bridge.DUST());

        (, uint256 outputValueB, ) = bridge.convert(
            inputAssetA,
            inputAssetB,
            outputAssetA,
            outputAssetB,
            inputValue,
            1,
            MAX_FEE,
            address(0)
        );

        // Transfer LUSD back to the rollupProcessor
        IERC20(outputAssetB.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueB);

        (uint256 debtAfterRepaying, , , ) = TROVE_MANAGER.getEntireDebtAndColl(address(bridge));
        uint256 expectedAmtLusdReturned = inputValue - (debtAfterRedemption - debtAfterRepaying);

        // Check the bridge doesn't hold any ETH or LUSD
        assertEq(address(bridge).balance, 0, "Bridge holds ETH after interaction");
        assertEq(tokens["LUSD"].erc.balanceOf(address(bridge)), bridge.DUST(), "Bridge holds LUSD after interaction");

        assertEq(outputValueB, expectedAmtLusdReturned, "Amount of LUSD returned doesn't equal expected amount");

        // Close the trove
        (uint256 remainingDebt, , , ) = TROVE_MANAGER.getEntireDebtAndColl(address(bridge));
        uint256 ownerEthBalanceBefore = OWNER.balance;

        vm.startPrank(OWNER);
        tokens["LUSD"].erc.approve(address(bridge), remainingDebt - 200e18);
        bridge.closeTrove();
        vm.stopPrank();

        uint256 ownerEthBalanceAfter = OWNER.balance;
        assertGt(
            ownerEthBalanceAfter,
            ownerEthBalanceBefore,
            "Owner's ETH balance didn't rise after closing the trove"
        );

        // Try reopening the trove
        deal(tokens["LUSD"].addr, OWNER, 0); // delete user's LUSD balance to make accounting easier in _openTrove(...)
        _openTrove();
    }

    // @dev run against a block when the flash swap doesn't fail
    function testRedistributionSuccessfulSwap() public {
        _setUpRedistribution();

        // Setting maxEthDelta to 0.05 ETH because there is some loss during swap
        _repay(ROLLUP_PROCESSOR_ETH_BALANCE * 3, 5e16, true, 1);

        _closeTroveAfterRedistribution(OWNER_ETH_BALANCE);

        // Try reopening the trove
        deal(tokens["LUSD"].addr, OWNER, 0); // delete user's LUSD balance to make accounting easier in _openTrove(...)
        _openTrove();
    }

    function testRedistributionExitWhenICREqualsMCR() public {
        vm.prank(OWNER);
        bridge = new TroveBridge(rollupProcessor, 500);

        _openTrove();
        _borrow(ROLLUP_PROCESSOR_ETH_BALANCE);

        // Erase stability pool's LUSD balance
        deal(tokens["LUSD"].addr, STABILITY_POOL, 0);

        uint256 priceBeforeDrop = TROVE_MANAGER.priceFeed().fetchPrice();

        setLiquityPrice(LIQUITY_PRICE_FEED.fetchPrice() / 2);
        TROVE_MANAGER.liquidateTroves(10);

        _borrowAfterRedistribution();

        // Rise the price back so that the system is not in recovery mode - allows me to drop trove's CR for a bit
        setLiquityPrice(priceBeforeDrop);

        // Drop Trove's CR to MCR by impersonating the bridge and directly withdrawing collateral
        (uint256 debt, uint256 coll, , ) = TROVE_MANAGER.getEntireDebtAndColl(address(bridge));

        uint256 icrAfterRedistribution = (coll * priceBeforeDrop) / debt;

        uint256 collToWithdraw = ((icrAfterRedistribution - MCR) * coll) / icrAfterRedistribution;

        address upperHint = SORTED_TROVES.getPrev(address(this));
        address lowerHint = SORTED_TROVES.getNext(address(this));
        vm.startPrank(address(bridge));
        BORROWER_OPERATIONS.withdrawColl(collToWithdraw, upperHint, lowerHint);
        vm.stopPrank();

        // Erase withdrawn collateral from the bridge
        vm.deal(address(bridge), 0);

        (debt, coll, , ) = TROVE_MANAGER.getEntireDebtAndColl(address(bridge));
        uint256 icrAfterWithdrawal = (coll * priceBeforeDrop) / debt;

        assertEq(icrAfterWithdrawal, MCR, "ICR after withdrawal doesn't equal MCR");

        // Setting maxEthDelta to 0.05 ETH because there is some loss during swap
        uint256 expectedBalance = (coll * bridge.balanceOf(rollupProcessor)) / bridge.totalSupply();
        _repay(expectedBalance, 5e16, true, 1);

        (, coll, , ) = TROVE_MANAGER.getEntireDebtAndColl(address(bridge));
        uint256 expectedOwnerBalance = (coll * bridge.balanceOf(OWNER)) / bridge.totalSupply();
        _closeTroveAfterRedistribution(expectedOwnerBalance);

        // Try reopening the trove
        deal(tokens["LUSD"].addr, OWNER, 0); // delete user's LUSD balance to make accounting easier in _openTrove(...)
        _openTrove();
    }

    // @dev run against a block when the flash swap fails - e.g. block 14972101 (pool was lacking liquidity)
    function testRedistributionFailingSwap() public {
        _setUpRedistribution();

        uint256 tbBalanceBefore = bridge.balanceOf(rollupProcessor);
        uint256 tbTotalSupplyBefore = bridge.totalSupply();

        // Disable balance check by setting max delta to high value - balance is expected to differ since
        // only a part of the debt should get repaid
        _repay(0, type(uint256).max, true, 1);

        uint256 tbTotalSupplyAfter1 = bridge.totalSupply();
        uint256 tbBalanceAfter1 = bridge.balanceOf(rollupProcessor);

        assertLt(tbBalanceAfter1, tbBalanceBefore, "TB balance didn't drop");
        assertLt(tbTotalSupplyAfter1, tbTotalSupplyBefore, "TB total supply didn't drop");
        assertGt(tbBalanceAfter1, 0, "All the debt was unexpectedly repaid");

        // Since some of TB got returned, try repaying one more time
        _repay(0, type(uint256).max, true, 3);

        uint256 tbTotalSupplyAfter2 = bridge.totalSupply();
        uint256 tbBalanceAfter2 = bridge.balanceOf(rollupProcessor);

        assertLt(tbBalanceAfter2, tbBalanceAfter1, "TB balance didn't drop in the second run");
        assertLt(tbTotalSupplyAfter2, tbTotalSupplyAfter1, "TB total supply didn't drop in the second run");
        assertGt(tbBalanceAfter2, 0, "All the debt was unexpectedly repaid in the second run");

        // Reopening the trove doesn't make sense here because user didn't burn his full TB balance
    }

    function _borrow(uint256 _collateral) private {
        vm.deal(address(bridge), _collateral);

        uint256 price = TROVE_MANAGER.priceFeed().fetchPrice();
        uint256 icrBeforeBorrowing = TROVE_MANAGER.getCurrentICR(address(bridge), price);

        (, uint256 collBeforeBorrowing, , ) = TROVE_MANAGER.getEntireDebtAndColl(address(bridge));

        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset(3, address(0), AztecTypes.AztecAssetType.ETH);
        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset(
            2,
            address(bridge),
            AztecTypes.AztecAssetType.ERC20
        );
        AztecTypes.AztecAsset memory outputAssetB = AztecTypes.AztecAsset(
            1,
            tokens["LUSD"].addr,
            AztecTypes.AztecAssetType.ERC20
        );

        // Borrow against collateral
        (uint256 outputValueA, uint256 outputValueB, ) = bridge.convert(
            inputAssetA,
            emptyAsset,
            outputAssetA,
            outputAssetB,
            _collateral,
            0,
            MAX_FEE,
            address(0)
        );

        // Transfer TB and LUSD back to the rollupProcessor
        IERC20(outputAssetA.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueA);
        IERC20(outputAssetB.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueB);

        (uint256 debtAfterBorrowing, uint256 collAfterBorrowing, , ) = TROVE_MANAGER.getEntireDebtAndColl(
            address(bridge)
        );
        assertEq(
            collAfterBorrowing - collBeforeBorrowing,
            _collateral,
            "Collateral increase differs from deposited collateral"
        );

        uint256 icrAfterBorrowing = TROVE_MANAGER.getCurrentICR(address(bridge), price);
        assertEq(icrBeforeBorrowing, icrAfterBorrowing, "ICR changed");

        assertEq(bridge.totalSupply(), debtAfterBorrowing, "TB total supply doesn't equal totalDebt");

        assertEq(address(bridge).balance, 0, "Bridge holds ETH after interaction");
        assertEq(tokens["LUSD"].erc.balanceOf(address(bridge)), bridge.DUST(), "Bridge holds LUSD after interaction");

        // Check the tokens were successfully sent to the rollupProcessor
        assertGt(bridge.balanceOf(rollupProcessor), 0, "Rollup processor doesn't hold any TB");
        assertGt(tokens["LUSD"].erc.balanceOf(rollupProcessor), 0, "Rollup processor doesn't hold any LUSD");
    }

    function _setUpRedistribution() private {
        vm.prank(OWNER);
        bridge = new TroveBridge(rollupProcessor, 500);

        _openTrove();
        _borrow(ROLLUP_PROCESSOR_ETH_BALANCE);

        (uint256 debtBefore, uint256 collBefore, , ) = TROVE_MANAGER.getEntireDebtAndColl(address(bridge));

        // Erase stability pool's LUSD balance in order to force redistribution
        deal(tokens["LUSD"].addr, STABILITY_POOL, 0);

        uint256 priceBeforeDrop = TROVE_MANAGER.priceFeed().fetchPrice();

        setLiquityPrice(LIQUITY_PRICE_FEED.fetchPrice() / 2);
        TROVE_MANAGER.liquidateTroves(10);

        (uint256 debtAfter, uint256 collAfter, , ) = TROVE_MANAGER.getEntireDebtAndColl(address(bridge));

        assertGt(debtAfter, debtBefore, "Debt hasn't increased after liquidations");
        assertGt(collAfter, collBefore, "Collateral hasn't increased after liquidations");

        _borrowAfterRedistribution();

        // Rise the price back so that the system is not in recovery mode - allows me to drop trove's CR for a bit
        setLiquityPrice(priceBeforeDrop);
    }

    function _repay(
        uint256 _expectedBalance,
        uint256 _maxEthDelta,
        bool _afterRedistribution,
        uint256 _interactionNonce
    ) private {
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset(
            2,
            address(bridge),
            AztecTypes.AztecAssetType.ERC20
        );
        AztecTypes.AztecAsset memory inputAssetB = AztecTypes.AztecAsset(
            1,
            tokens["LUSD"].addr,
            AztecTypes.AztecAssetType.ERC20
        );
        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset(3, address(0), AztecTypes.AztecAssetType.ETH);
        AztecTypes.AztecAsset memory outputAssetB = _afterRedistribution
            ? AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20)
            : AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20);

        // inputValue is equal to rollupProcessor TB balance --> we want to repay the debt in full
        uint256 inputValue = bridge.balanceOf(rollupProcessor);
        // Transfer TB to the bridge
        IERC20(inputAssetA.erc20Address).transfer(address(bridge), inputValue);

        // Mint the amount to repay to the bridge
        deal(inputAssetB.erc20Address, address(bridge), inputValue + bridge.DUST());

        uint256 rollupProcessorEthBalanceBefore = rollupProcessor.balance;

        (uint256 outputValueA, uint256 outputValueB, ) = bridge.convert(
            inputAssetA,
            inputAssetB,
            outputAssetA,
            outputAssetB,
            inputValue,
            _interactionNonce,
            MAX_FEE,
            address(0)
        );

        uint256 rollupProcessorEthBalanceDiff = rollupProcessor.balance - rollupProcessorEthBalanceBefore;
        assertEq(rollupProcessorEthBalanceDiff, outputValueA, "ETH received differs from outputValueA");

        // Transfer LUSD or TB back to the rollupProcessor
        IERC20(outputAssetB.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueB);

        // Check that the bridge doesn't hold any ETH or LUSD
        assertEq(address(bridge).balance, 0, "Bridge holds ETH after interaction");
        assertEq(tokens["LUSD"].erc.balanceOf(address(bridge)), bridge.DUST(), "Bridge holds LUSD after interaction");

        assertApproxEqAbs(
            rollupProcessorEthBalanceDiff,
            _expectedBalance,
            _maxEthDelta,
            "Current rollup processor ETH balance differs from the expected balance by more than maxEthDelta"
        );
    }

    function _redeem() private {
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset(
            2,
            address(bridge),
            AztecTypes.AztecAssetType.ERC20
        );
        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset(3, address(0), AztecTypes.AztecAssetType.ETH);

        // inputValue is equal to rollupProcessor TB balance --> we want to redeem remaining collateral in full
        uint256 inputValue = bridge.balanceOf(rollupProcessor);
        // Transfer TB to the bridge
        IERC20(inputAssetA.erc20Address).transfer(address(bridge), inputValue);

        bridge.convert(inputAssetA, emptyAsset, outputAssetA, emptyAsset, inputValue, 1, 0, address(0));

        assertGt(rollupProcessor.balance, 0, "No ETH has been redeemed");
    }

    function _borrowAfterRedistribution() private {
        uint256 depositAmount = ROLLUP_PROCESSOR_ETH_BALANCE * 2;
        vm.deal(rollupProcessor, depositAmount);

        uint256 price = TROVE_MANAGER.priceFeed().fetchPrice();
        uint256 icrBeforeBorrowing = TROVE_MANAGER.getCurrentICR(address(bridge), price);

        (, uint256 collBeforeBorrowing, , ) = TROVE_MANAGER.getEntireDebtAndColl(address(bridge));

        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset(3, address(0), AztecTypes.AztecAssetType.ETH);
        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset(
            2,
            address(bridge),
            AztecTypes.AztecAssetType.ERC20
        );
        AztecTypes.AztecAsset memory outputAssetB = AztecTypes.AztecAsset(
            1,
            tokens["LUSD"].addr,
            AztecTypes.AztecAssetType.ERC20
        );

        // Borrow against ROLLUP_PROCESSOR_ETH_BALANCE
        (uint256 outputValueA, uint256 outputValueB, ) = bridge.convert{value: depositAmount}(
            inputAssetA,
            emptyAsset,
            outputAssetA,
            outputAssetB,
            depositAmount,
            2,
            MAX_FEE,
            address(0)
        );

        // Transfer TB and LUSD back to the rollupProcessor
        IERC20(outputAssetA.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueA);
        IERC20(outputAssetB.erc20Address).transferFrom(address(bridge), rollupProcessor, outputValueB);

        (uint256 debtAfterBorrowing, uint256 collAfterBorrowing, , ) = TROVE_MANAGER.getEntireDebtAndColl(
            address(bridge)
        );
        assertEq(
            collAfterBorrowing - collBeforeBorrowing,
            depositAmount,
            "Collateral increase differs from depositAmount"
        );

        uint256 icrAfterBorrowing = TROVE_MANAGER.getCurrentICR(address(bridge), price);
        assertEq(icrBeforeBorrowing, icrAfterBorrowing, "ICR changed");

        assertLt(bridge.totalSupply(), debtAfterBorrowing, "TB total supply isn't bigger than totalDebt");

        assertEq(address(bridge).balance, 0, "Bridge holds ETH after interaction");
        assertEq(tokens["LUSD"].erc.balanceOf(address(bridge)), bridge.DUST(), "Bridge holds LUSD after interaction");
    }
}
