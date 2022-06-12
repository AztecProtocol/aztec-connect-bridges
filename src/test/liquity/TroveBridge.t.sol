// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {AztecTypes} from "../../aztec/AztecTypes.sol";

import {TestUtil} from "./utils/TestUtil.sol";
import {IHintHelpers} from "./interfaces/IHintHelpers.sol";
import {TroveBridge} from "../../bridges/liquity/TroveBridge.sol";
import {ISortedTroves} from "../../bridges/liquity/interfaces/ISortedTroves.sol";

contract TroveBridgeTest is TestUtil {
    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation,
        closedByRedemption
    }

    IHintHelpers private constant HINT_HELPERS = IHintHelpers(0xE84251b93D9524E0d2e621Ba7dc7cb3579F997C0);
    ISortedTroves private constant SORTED_TROVES = ISortedTroves(0x8FdD3fbFEb32b28fb73555518f8b361bCeA741A6);
    address private constant STABILITY_POOL = 0x66017D22b0f8556afDd19FC67041899Eb65a21bb;

    address private constant OWNER = address(24);

    uint256 private constant OWNER_WEI_BALANCE = 5e18; // 5 ETH
    uint256 private constant ROLLUP_PROCESSOR_WEI_BALANCE = 1e18; // 1 ETH

    uint64 private constant MAX_FEE = 5e16; // Slippage protection: 5%
    uint256 public constant MCR = 1100000000000000000; // 110%

    // From LiquityMath.sol
    uint256 private constant NICR_PRECISION = 1e20;

    TroveBridge private bridge;

    receive() external payable {}

    // Here so that I can successfully liquidate a trove from within this contract.
    fallback() external payable {}

    function setUp() public {
        _aztecPreSetup();
        setUpTokens();

        uint256 initialCollateralRatio = 160;

        vm.prank(OWNER);
        bridge = new TroveBridge(address(rollupProcessor), initialCollateralRatio);

        vm.label(address(bridge.USDC()), "USDC");
        vm.label(address(bridge.BORROWER_OPERATIONS()), "BORROWER_OPERATIONS");
        vm.label(address(bridge.TROVE_MANAGER()), "TROVE_MANAGER");
        vm.label(address(bridge.SORTED_TROVES()), "SORTED_TROVES");
        vm.label(address(bridge.LUSD_USDC_POOL()), "LUSD_USDC_POOL");
        vm.label(address(bridge.USDC_ETH_POOL()), "USDC_ETH_POOL");
        vm.label(address(LIQUITY_PRICE_FEED), "LIQUITY_PRICE_FEED");
        vm.label(0x66017D22b0f8556afDd19FC67041899Eb65a21bb, "STABILITY_POOL");
        vm.label(0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d, "LQTY_STAKING_CONTRACT");

        // Set OWNER's and ROLLUP_PROCESSOR's balances
        vm.deal(OWNER, OWNER_WEI_BALANCE);

        // Set LUSD bridge balance to 1 WEI
        // Necessary for the optimization based on EIP-1087 to work!
        deal(tokens["LUSD"].addr, address(bridge), 1);
    }

    function testInitialERC20Params() public {
        assertEq(bridge.name(), "TroveBridge");
        assertEq(bridge.symbol(), "TB-160");
        assertEq(uint256(bridge.decimals()), 18);
    }

    function testIncorrectTroveState() public {
        // Attempt borrowing when trove was not opened - state 0
        vm.deal(address(rollupProcessor), ROLLUP_PROCESSOR_WEI_BALANCE);
        vm.prank(address(rollupProcessor));
        vm.expectRevert(abi.encodeWithSignature("IncorrectStatus(uint8,uint8)", 1, 0));
        bridge.convert(
            AztecTypes.AztecAsset(3, address(0), AztecTypes.AztecAssetType.ETH),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            ROLLUP_PROCESSOR_WEI_BALANCE,
            0,
            MAX_FEE,
            address(0)
        );
    }

    function testIncorrectInput() public {
        // Call convert with incorrect input
        vm.prank(address(rollupProcessor));
        vm.expectRevert(TroveBridge.IncorrectInput.selector);
        bridge.convert(
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
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
        _borrow(ROLLUP_PROCESSOR_WEI_BALANCE);
        _repay(ROLLUP_PROCESSOR_WEI_BALANCE, 1);
        _closeTrove();
    }

    function testLiquidationFlow() public {
        _openTrove();
        _borrow(ROLLUP_PROCESSOR_WEI_BALANCE);

        // Drop price and liquidate the trove
        setLiquityPrice(LIQUITY_PRICE_FEED.fetchPrice() / 2);
        bridge.TROVE_MANAGER().liquidate(address(bridge));
        Status troveStatus = Status(bridge.TROVE_MANAGER().getTroveStatus(address(bridge)));
        assertTrue(troveStatus == Status.closedByLiquidation, "Incorrect trove status");

        // Set msg.sender to OWNER
        vm.startPrank(OWNER);

        // Bridge is now defunct so check that closing and reopening fails with appropriate errors
        vm.expectRevert(TroveBridge.OwnerNotLast.selector);
        bridge.closeTrove();

        vm.expectRevert(TroveBridge.NonZeroTotalSupply.selector);
        bridge.openTrove(address(0), address(0), MAX_FEE);

        vm.stopPrank();
    }

    function testRedeemFlow() public {
        vm.prank(OWNER);
        bridge = new TroveBridge(address(rollupProcessor), 110);

        _openTrove();
        _borrow(ROLLUP_PROCESSOR_WEI_BALANCE);

        address lowestIcrTrove = bridge.SORTED_TROVES().getLast();
        assertEq(lowestIcrTrove, address(bridge), "Bridge's trove is not the first one to redeem.");

        (uint256 debtBefore, , , ) = bridge.TROVE_MANAGER().getEntireDebtAndColl(address(bridge));

        uint256 amountToRedeem = debtBefore * 2;

        uint256 price = bridge.TROVE_MANAGER().priceFeed().fetchPrice();

        (, uint256 partialRedemptionHintNICR, ) = HINT_HELPERS.getRedemptionHints(amountToRedeem, price, 0);

        (address approxPartialRedemptionHint, , ) = HINT_HELPERS.getApproxHint(partialRedemptionHintNICR, 50, 42);

        (address exactUpperPartialRedemptionHint, address exactLowerPartialRedemptionHint) = SORTED_TROVES
            .findInsertPosition(partialRedemptionHintNICR, approxPartialRedemptionHint, approxPartialRedemptionHint);

        // Keep on redeeming 20 million LUSD until the trove is in the closedByRedemption status
        deal(tokens["LUSD"].addr, address(this), amountToRedeem);
        bridge.TROVE_MANAGER().redeemCollateral(
            amountToRedeem,
            lowestIcrTrove,
            exactUpperPartialRedemptionHint,
            exactLowerPartialRedemptionHint,
            partialRedemptionHintNICR,
            0,
            1e18
        );

        assertEq(
            bridge.TROVE_MANAGER().getTroveStatus(address(bridge)),
            4,
            "Status is not closedByRedemption"
        );

        _redeem();
        _closeRedeem();
    }

    function testPartialRedeemFlow() public {
        vm.prank(OWNER);
        bridge = new TroveBridge(address(rollupProcessor), 110);

        _openTrove();
        _borrow(60 ether);

        address lowestIcrTrove = bridge.SORTED_TROVES().getLast();
        assertEq(lowestIcrTrove, address(bridge), "Bridge's trove is not the first one to redeem.");

        (uint256 debtBefore, , , ) = bridge.TROVE_MANAGER().getEntireDebtAndColl(address(bridge));

        uint256 amountToRedeem = debtBefore / 2;

        uint256 price = bridge.TROVE_MANAGER().priceFeed().fetchPrice();

        (, uint256 partialRedemptionHintNICR, ) = HINT_HELPERS.getRedemptionHints(amountToRedeem, price, 0);

        (address approxPartialRedemptionHint, , ) = HINT_HELPERS.getApproxHint(partialRedemptionHintNICR, 50, 42);

        (address exactUpperPartialRedemptionHint, address exactLowerPartialRedemptionHint) = SORTED_TROVES
            .findInsertPosition(partialRedemptionHintNICR, approxPartialRedemptionHint, approxPartialRedemptionHint);

        deal(tokens["LUSD"].addr, address(this), amountToRedeem);
        bridge.TROVE_MANAGER().redeemCollateral(
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
        (uint256 debtAfterRedemption, , , ) = bridge.TROVE_MANAGER().getEntireDebtAndColl(address(bridge));
        assertEq(
            debtAfterRedemption,
            debtBefore - amountToRedeem,
            "Debt amount isn't equal to original debt - amount redeemed"
        );

        uint256 status = bridge.TROVE_MANAGER().getTroveStatus(address(bridge));
        assertEq(status, uint256(Status.active), "Status is not active");

        // Repay and see whether the returned amount of LUSD is as expected
        uint256 processorTBBalance = bridge.balanceOf(address(rollupProcessor));

        // Mint the borrower fee to ROLLUP_PROCESSOR in order to have a big enough balance for repaying
        // borrowerFee = processorTBBalance - processorLUSDBalance;
        deal(tokens["LUSD"].addr, address(rollupProcessor), processorTBBalance);

        (, uint256 amtLusdReturned, ) = rollupProcessor.convert(
            address(bridge),
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(3, address(0), AztecTypes.AztecAssetType.ETH),
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            processorTBBalance,
            1,
            MAX_FEE
        );

        (uint256 debtAfterRepaying, , , ) = bridge.TROVE_MANAGER().getEntireDebtAndColl(address(bridge));
        uint256 expectedAmtLusdReturned = processorTBBalance - (debtAfterRedemption - debtAfterRepaying);

        // Check the bridge doesn't hold any ETH or LUSD
        assertEq(address(bridge).balance, 0, "Bridge holds ETH after interaction");
        assertEq(tokens["LUSD"].erc.balanceOf(address(bridge)), bridge.DUST(), "Bridge holds LUSD after interaction");

        assertEq(amtLusdReturned, expectedAmtLusdReturned, "Amount of LUSD returned doesn't equal expected amount");
    }

    function testRedistribution() public {
        vm.prank(OWNER);
        bridge = new TroveBridge(address(rollupProcessor), 500);

        _openTrove();
        _borrow(ROLLUP_PROCESSOR_WEI_BALANCE);

        (uint256 debtBefore, uint256 collBefore, , ) = bridge.TROVE_MANAGER().getEntireDebtAndColl(address(bridge));

        // Erase stability pool's LUSD balance
        deal(tokens["LUSD"].addr, STABILITY_POOL, 0);

        uint256 priceBeforeDrop = bridge.TROVE_MANAGER().priceFeed().fetchPrice();

        setLiquityPrice(LIQUITY_PRICE_FEED.fetchPrice() / 2);
        bridge.TROVE_MANAGER().liquidateTroves(10);

        (uint256 debtAfter, uint256 collAfter, , ) = bridge.TROVE_MANAGER().getEntireDebtAndColl(address(bridge));

        assertGt(debtAfter, debtBefore, "Debt hasn't increased after liquidations");
        assertGt(collAfter, collBefore, "Collateral hasn't increased after liquidations");

        _borrowAfterRedistribution();

        // Rise the price back so that the system is not in recovery mode - allows me to drop trove's CR for a bit
        setLiquityPrice(priceBeforeDrop);

        // Setting maxEthDelta to 0.05 ETH because there is some loss during swap
        _repay(ROLLUP_PROCESSOR_WEI_BALANCE * 3, 5e16);

        _closeTroveAfterRedistribution(OWNER_WEI_BALANCE);
    }

    function testExitWhenICREqualsMCRAfterRedistribution() public {
        vm.prank(OWNER);
        bridge = new TroveBridge(address(rollupProcessor), 500);

        _openTrove();
        _borrow(ROLLUP_PROCESSOR_WEI_BALANCE);

        // Erase stability pool's LUSD balance
        deal(tokens["LUSD"].addr, STABILITY_POOL, 0);

        uint256 priceBeforeDrop = bridge.TROVE_MANAGER().priceFeed().fetchPrice();

        setLiquityPrice(LIQUITY_PRICE_FEED.fetchPrice() / 2);
        bridge.TROVE_MANAGER().liquidateTroves(10);

        _borrowAfterRedistribution();

        // Rise the price back so that the system is not in recovery mode - allows me to drop trove's CR for a bit
        setLiquityPrice(priceBeforeDrop);

        // Drop Trove's CR to MCR by impersonating the bridge and directly withdrawing collateral
        (uint256 debt, uint256 coll, , ) = bridge.TROVE_MANAGER().getEntireDebtAndColl(address(bridge));

        uint256 icrAfterRedistribution = (coll * priceBeforeDrop) / debt;

        uint256 collToWithdraw = ((icrAfterRedistribution - MCR) * coll) / icrAfterRedistribution;

        address upperHint = bridge.SORTED_TROVES().getPrev(address(this));
        address lowerHint = bridge.SORTED_TROVES().getNext(address(this));
        vm.startPrank(address(bridge));
        bridge.BORROWER_OPERATIONS().withdrawColl(collToWithdraw, upperHint, lowerHint);
        vm.stopPrank();

        // Erase withdrawn collateral from the bridge
        vm.deal(address(bridge), 0);

        (debt, coll, , ) = bridge.TROVE_MANAGER().getEntireDebtAndColl(address(bridge));
        uint256 icrAfterWithdrawal = (coll * priceBeforeDrop) / debt;

        assertEq(icrAfterWithdrawal, MCR, "ICR after withdrawal doesn't equal MCR");

        // Setting maxEthDelta to 0.05 ETH because there is some loss during swap
        uint256 expectedBalance = (coll * bridge.balanceOf(address(rollupProcessor))) / bridge.totalSupply();
        _repay(expectedBalance, 5e16);

        (, coll, , ) = bridge.TROVE_MANAGER().getEntireDebtAndColl(address(bridge));
        uint256 expectedOwnerBalance = (coll * bridge.balanceOf(OWNER)) / bridge.totalSupply();
        _closeTroveAfterRedistribution(expectedOwnerBalance);
    }

    function _openTrove() private {
        // Set msg.sender to OWNER
        vm.startPrank(OWNER);

        uint256 amtToBorrow = bridge.computeAmtToBorrow(OWNER_WEI_BALANCE);
        uint256 nicr = (OWNER_WEI_BALANCE * NICR_PRECISION) / amtToBorrow;

        // The following is Solidity implementation of https://github.com/liquity/dev#opening-a-trove
        uint256 numTrials = 15;
        uint256 randomSeed = 42;
        (address approxHint, , ) = HINT_HELPERS.getApproxHint(nicr, numTrials, randomSeed);
        (address upperHint, address lowerHint) = SORTED_TROVES.findInsertPosition(nicr, approxHint, approxHint);

        // Open the trove
        bridge.openTrove{value: OWNER_WEI_BALANCE}(upperHint, lowerHint, MAX_FEE);

        uint256 price = bridge.TROVE_MANAGER().priceFeed().fetchPrice();
        uint256 icr = bridge.TROVE_MANAGER().getCurrentICR(address(bridge), price);
        assertEq(icr, bridge.INITIAL_ICR(), "ICR doesn't equal initial ICR");

        (uint256 debtAfterBorrowing, uint256 collAfterBorrowing, , ) = bridge.TROVE_MANAGER().getEntireDebtAndColl(
            address(bridge)
        );
        assertEq(bridge.totalSupply(), debtAfterBorrowing, "TB total supply doesn't equal totalDebt");
        assertEq(collAfterBorrowing, OWNER_WEI_BALANCE, "Trove's collateral doesn't equal deposit amount");

        uint256 lusdBalance = tokens["LUSD"].erc.balanceOf(OWNER);
        assertApproxEqAbs(lusdBalance, amtToBorrow, 1, "Borrowed amount differs from received by more than 1 wei");

        assertEq(address(bridge).balance, 0, "Bridge holds ETH after trove opening");
        assertEq(tokens["LUSD"].erc.balanceOf(address(bridge)), bridge.DUST(), "Bridge holds LUSD after trove opening");

        vm.stopPrank();
    }

    function _borrow(uint256 _collateral) private {
        vm.deal(address(rollupProcessor), _collateral);

        uint256 price = bridge.TROVE_MANAGER().priceFeed().fetchPrice();
        uint256 icrBeforeBorrowing = bridge.TROVE_MANAGER().getCurrentICR(address(bridge), price);

        (, uint256 collBeforeBorrowing, , ) = bridge.TROVE_MANAGER().getEntireDebtAndColl(address(bridge));

        // Borrow against collateral
        rollupProcessor.convert(
            address(bridge),
            AztecTypes.AztecAsset(3, address(0), AztecTypes.AztecAssetType.ETH),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            _collateral,
            0,
            MAX_FEE
        );

        (uint256 debtAfterBorrowing, uint256 collAfterBorrowing, , ) = bridge.TROVE_MANAGER().getEntireDebtAndColl(
            address(bridge)
        );
        assertEq(
            collAfterBorrowing - collBeforeBorrowing,
            _collateral,
            "Collateral increase differs from deposited collateral"
        );

        uint256 icrAfterBorrowing = bridge.TROVE_MANAGER().getCurrentICR(address(bridge), price);
        assertEq(icrBeforeBorrowing, icrAfterBorrowing, "ICR changed");

        assertEq(bridge.totalSupply(), debtAfterBorrowing, "TB total supply doesn't equal totalDebt");

        assertEq(address(bridge).balance, 0, "Bridge holds ETH after interaction");
        assertEq(tokens["LUSD"].erc.balanceOf(address(bridge)), bridge.DUST(), "Bridge holds LUSD after interaction");

        // Check the tokens were successfully sent to the rollupProcessor
        assertGt(bridge.balanceOf(address(rollupProcessor)), 0, "Rollup processor doesn't hold any TB");
        assertGt(tokens["LUSD"].erc.balanceOf(address(rollupProcessor)), 0, "Rollup processor doesn't hold any LUSD");
    }

    function _repay(uint256 _expectedBalance, uint256 _maxEthDelta) private {
        uint256 processorTBBalance = bridge.balanceOf(address(rollupProcessor));

        // Mint the borrower fee to ROLLUP_PROCESSOR in order to have a big enough balance for repaying
        // borrowerFee = processorTBBalance - processorLUSDBalance;
        deal(tokens["LUSD"].addr, address(rollupProcessor), processorTBBalance);

        rollupProcessor.convert(
            address(bridge),
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(3, address(0), AztecTypes.AztecAssetType.ETH),
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            processorTBBalance,
            1,
            MAX_FEE
        );

        // Check the bridge doesn't hold any ETH or LUSD
        assertEq(address(bridge).balance, 0, "Bridge holds ETH after interaction");
        assertEq(tokens["LUSD"].erc.balanceOf(address(bridge)), bridge.DUST(), "Bridge holds LUSD after interaction");

        assertApproxEqAbs(
            address(rollupProcessor).balance,
            _expectedBalance,
            _maxEthDelta,
            "Current rollup processor balance differs from the expected balance by more than maxEthDelta"
        );
    }

    function _closeTrove() private {
        // Set msg.sender to OWNER
        vm.startPrank(OWNER);

        uint256 ownerTBBalance = bridge.balanceOf(OWNER);
        uint256 ownerLUSDBalance = tokens["LUSD"].erc.balanceOf(OWNER);

        uint256 borrowerFee = ownerTBBalance - ownerLUSDBalance - 200e18;
        uint256 amountToRepay = ownerLUSDBalance + borrowerFee;

        // Increase OWNER's LUSD balance by borrowerFee
        deal(tokens["LUSD"].addr, OWNER, amountToRepay);
        tokens["LUSD"].erc.approve(address(bridge), amountToRepay);

        bridge.closeTrove();

        Status troveStatus = Status(bridge.TROVE_MANAGER().getTroveStatus(address(bridge)));
        assertTrue(troveStatus == Status.closedByOwner, "Incorrect trove status");

        assertEq(address(bridge).balance, 0, "Bridge holds ETH after trove closure");
        assertEq(tokens["LUSD"].erc.balanceOf(address(bridge)), bridge.DUST(), "Bridge holds LUSD after trove closure");

        assertApproxEqAbs(
            OWNER.balance,
            OWNER_WEI_BALANCE,
            1,
            "Current owner balance differs from the initial balance by more than 1 wei"
        );

        assertEq(bridge.totalSupply(), 0, "TB total supply is not 0 after trove closure");

        vm.stopPrank();
    }

    function _redeem() private {
        uint256 processorTBBalance = bridge.balanceOf(address(rollupProcessor));

        rollupProcessor.convert(
            address(bridge),
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(3, address(0), AztecTypes.AztecAssetType.ETH),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            processorTBBalance,
            1,
            0
        );

        assertGt(address(rollupProcessor).balance, 0, "No ETH has been redeemed");
    }

    function _closeRedeem() private {
        // Set msg.sender to OWNER
        vm.startPrank(OWNER);

        bridge.closeTrove();

        assertEq(address(bridge).balance, 0, "Bridge holds ETH after trove closing");

        assertGt(OWNER.balance, 0, "No ETH has been redeemed");

        assertEq(bridge.totalSupply(), 0, "TB total supply is not 0");

        vm.stopPrank();
    }

    function _borrowAfterRedistribution() private {
        uint256 depositAmount = ROLLUP_PROCESSOR_WEI_BALANCE * 2;
        vm.deal(address(rollupProcessor), depositAmount);

        uint256 price = bridge.TROVE_MANAGER().priceFeed().fetchPrice();
        uint256 icrBeforeBorrowing = bridge.TROVE_MANAGER().getCurrentICR(address(bridge), price);

        (, uint256 collBeforeBorrowing, , ) = bridge.TROVE_MANAGER().getEntireDebtAndColl(address(bridge));

        // Borrow against ROLLUP_PROCESSOR_WEI_BALANCE
        rollupProcessor.convert(
            address(bridge),
            AztecTypes.AztecAsset(3, address(0), AztecTypes.AztecAssetType.ETH),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            depositAmount,
            2,
            MAX_FEE
        );

        (uint256 debtAfterBorrowing, uint256 collAfterBorrowing, , ) = bridge.TROVE_MANAGER().getEntireDebtAndColl(
            address(bridge)
        );
        assertEq(
            collAfterBorrowing - collBeforeBorrowing,
            depositAmount,
            "Collateral increase differs from depositAmount"
        );

        uint256 icrAfterBorrowing = bridge.TROVE_MANAGER().getCurrentICR(address(bridge), price);
        assertEq(icrBeforeBorrowing, icrAfterBorrowing, "ICR changed");

        assertLt(bridge.totalSupply(), debtAfterBorrowing, "TB total supply isn't bigger than totalDebt");

        assertEq(address(bridge).balance, 0, "Bridge holds ETH after interaction");
        assertEq(tokens["LUSD"].erc.balanceOf(address(bridge)), bridge.DUST(), "Bridge holds LUSD after interaction");
    }

    function _closeTroveAfterRedistribution(uint256 _expectedBalance) private {
        // Set msg.sender to OWNER
        vm.startPrank(OWNER);

        (uint256 debtBeforeClosure, , , ) = bridge.TROVE_MANAGER().getEntireDebtAndColl(address(bridge));

        uint256 amountToRepay = debtBeforeClosure - 200e18;

        // Increase OWNER's LUSD balance by borrowerFee
        deal(tokens["LUSD"].addr, OWNER, amountToRepay);
        tokens["LUSD"].erc.approve(address(bridge), amountToRepay);

        bridge.closeTrove();

        Status troveStatus = Status(bridge.TROVE_MANAGER().getTroveStatus(address(bridge)));
        assertTrue(troveStatus == Status.closedByOwner, "Incorrect trove status");

        assertEq(address(bridge).balance, 0, "Bridge holds ETH after trove closure");
        assertEq(tokens["LUSD"].erc.balanceOf(address(bridge)), bridge.DUST(), "Bridge holds LUSD after trove closure");

        assertApproxEqAbs(
            OWNER.balance,
            _expectedBalance,
            1e17,
            "Current owner balance differs from the initial balance by more than 0.1 ETH"
        );

        assertEq(bridge.totalSupply(), 0, "TB total supply is not 0 after trove closure");

        vm.stopPrank();
    }
}
