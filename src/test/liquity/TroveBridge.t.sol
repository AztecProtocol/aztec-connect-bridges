// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.0 <=0.8.10;
pragma abicoder v2;

import "./utils/TestUtil.sol";
import "./interfaces/IHintHelpers.sol";
import "../../bridges/liquity/TroveBridge.sol";

contract TroveBridgeTest is TestUtil {
    TroveBridge private bridge;

    IHintHelpers private constant hintHelpers = IHintHelpers(0xE84251b93D9524E0d2e621Ba7dc7cb3579F997C0);
    ISortedTroves private constant sortedTroves = ISortedTroves(0x8FdD3fbFEb32b28fb73555518f8b361bCeA741A6);

    address private constant OWNER = address(24);

    uint256 private constant OWNER_WEI_BALANCE = 5e18; // 5 ETH
    uint256 private constant ROLLUP_PROCESSOR_WEI_BALANCE = 1e18; // 1 ETH

    uint64 private constant MAX_FEE = 5e16; // Slippage protection: 5%

    // From LiquityMath.sol
    uint256 private constant NICR_PRECISION = 1e20;

    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation,
        closedByRedemption
    }

    function setUp() public {
        _aztecPreSetup();
        setUpTokens();

        uint256 initialCollateralRatio = 160;

        vm.prank(OWNER);
        bridge = new TroveBridge(address(rollupProcessor), initialCollateralRatio);

        // Set OWNER's and ROLLUP_PROCESSOR's balances
        vm.deal(OWNER, OWNER_WEI_BALANCE);
        vm.deal(address(rollupProcessor), ROLLUP_PROCESSOR_WEI_BALANCE);
    }

    function testInitialERC20Params() public {
        assertEq(bridge.name(), "TroveBridge");
        assertEq(bridge.symbol(), "TB-160");
        assertEq(uint256(bridge.decimals()), 18);
    }

    function testIncorrectTroveState() public {
        // Attempt borrowing when trove was not opened - state 0
        vm.prank(address(rollupProcessor));
        try
            bridge.convert(
                AztecTypes.AztecAsset(3, address(0), AztecTypes.AztecAssetType.ETH),
                AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
                AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
                AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
                ROLLUP_PROCESSOR_WEI_BALANCE,
                0,
                MAX_FEE,
                address(0)
            )
        {
            assertTrue(false, "convert(...) has to revert when trove is in an incorrect state.");
        } catch (bytes memory reason) {
            assertEq(TroveBridge.IncorrectStatus.selector, bytes4(reason));
        }
    }

    function testIncorrectInput() public {
        // Call convert with incorrect input
        vm.prank(address(rollupProcessor));
        try
            bridge.convert(
                AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
                AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
                AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
                AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
                0,
                0,
                0,
                address(0)
            )
        {
            assertTrue(false, "convert(...) has to revert on incorrect input.");
        } catch (bytes memory reason) {
            assertEq(TroveBridge.IncorrectInput.selector, bytes4(reason));
        }
    }

    function testFullFlow() public {
        // This is the only way how to make 1 part of test depend on another in DSTest because tests are otherwise ran
        // in parallel in different EVM instances. For this reason these parts of tests can't be evaluated individually
        // unless ran repeatedly.
        _openTrove();
        _borrow();
        _repay();
        _closeTrove();
    }

    function testLiquidationFlow() public {
        _openTrove();
        _borrow();

        // Drop price and liquidate the trove
        dropLiquityPriceByHalf();
        bridge.troveManager().liquidate(address(bridge));
        Status troveStatus = Status(bridge.troveManager().getTroveStatus(address(bridge)));
        assertTrue(troveStatus == Status.closedByLiquidation);

        // Set msg.sender to OWNER
        vm.startPrank(OWNER);

        // Bridge is now defunct so check that closing and reopening fails with appropriate errors
        try bridge.closeTrove() {
            assertTrue(false, "closeTrove() has to revert in case owner's balance != TB total supply.");
        } catch (bytes memory reason) {
            assertEq(TroveBridge.OwnerNotLast.selector, bytes4(reason));
        }

        try bridge.openTrove(address(0), address(0), MAX_FEE) {
            assertTrue(false, "openTrove() has to revert in case TB total supply != 0.");
        } catch (bytes memory reason) {
            assertEq(TroveBridge.NonZeroTotalSupply.selector, bytes4(reason));
        }

        vm.stopPrank();
    }

    function testRedeemFlow() public {
        _openTrove();
        _borrow();

        // Keep on redeeming 20 million LUSD until the trove is in the closedByRedemption status
        uint256 amountToRedeem = 2e25;
        do {
            deal(tokens["LUSD"].addr, address(this), amountToRedeem);
            bridge.troveManager().redeemCollateral(amountToRedeem, address(0), address(0), address(0), 0, 0, 1e18);
        } while (Status(bridge.troveManager().getTroveStatus(address(bridge))) != Status.closedByRedemption);

        _redeem();
    }

    function _openTrove() private {
        // Set msg.sender to OWNER
        vm.startPrank(OWNER);

        uint256 amtToBorrow = bridge.computeAmtToBorrow(OWNER_WEI_BALANCE);
        uint256 nicr = (OWNER_WEI_BALANCE * NICR_PRECISION) / amtToBorrow;

        // The following is Solidity implementation of https://github.com/liquity/dev#opening-a-trove
        uint256 numTrials = 15;
        uint256 randomSeed = 42;
        (address approxHint, , ) = hintHelpers.getApproxHint(nicr, numTrials, randomSeed);
        (address upperHint, address lowerHint) = sortedTroves.findInsertPosition(nicr, approxHint, approxHint);

        // Open the trove
        bridge.openTrove{value: OWNER_WEI_BALANCE}(upperHint, lowerHint, MAX_FEE);

        uint256 price = bridge.troveManager().priceFeed().fetchPrice();
        uint256 icr = bridge.troveManager().getCurrentICR(address(bridge), price);
        // Verify the ICR equals the one specified in the bridge constructor
        assertEq(icr, 160e16);

        (uint256 debtAfterBorrowing, uint256 collAfterBorrowing, , ) = bridge.troveManager().getEntireDebtAndColl(
            address(bridge)
        );
        // Check the TB total supply equals totalDebt
        assertEq(bridge.totalSupply(), debtAfterBorrowing);
        // Check the trove's collateral equals deposit amount
        assertEq(collAfterBorrowing, OWNER_WEI_BALANCE);

        uint256 lusdBalance = tokens["LUSD"].erc.balanceOf(OWNER);
        assertEq(lusdBalance, amtToBorrow);

        // Check the bridge doesn't hold any ETH or LUSD
        assertEq(address(bridge).balance, 0);
        assertEq(tokens["LUSD"].erc.balanceOf(address(bridge)), 0);

        vm.stopPrank();
    }

    function _borrow() private {
        uint256 price = bridge.troveManager().priceFeed().fetchPrice();
        uint256 icrBeforeBorrowing = bridge.troveManager().getCurrentICR(address(bridge), price);

        (, uint256 collBeforeBorrowing, , ) = bridge.troveManager().getEntireDebtAndColl(address(bridge));

        // Borrow against ROLLUP_PROCESSOR_WEI_BALANCE
        rollupProcessor.convert(
            address(bridge),
            AztecTypes.AztecAsset(3, address(0), AztecTypes.AztecAssetType.ETH),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            ROLLUP_PROCESSOR_WEI_BALANCE,
            0,
            MAX_FEE
        );

        (uint256 debtAfterBorrowing, uint256 collAfterBorrowing, , ) = bridge.troveManager().getEntireDebtAndColl(
            address(bridge)
        );
        // Check the collateral increase equals ROLLUP_PROCESSOR_WEI_BALANCE
        assertEq(collAfterBorrowing - collBeforeBorrowing, ROLLUP_PROCESSOR_WEI_BALANCE);

        uint256 icrAfterBorrowing = bridge.troveManager().getCurrentICR(address(bridge), price);
        // Check the the ICR didn't change
        assertEq(icrBeforeBorrowing, icrAfterBorrowing);

        // Check the TB total supply equals totalDebt
        assertEq(bridge.totalSupply(), debtAfterBorrowing);

        // Check the bridge doesn't hold any ETH or LUSD
        assertEq(address(bridge).balance, 0);
        assertEq(tokens["LUSD"].erc.balanceOf(address(bridge)), 0);

        // Check the tokens were successfully sent to the rollupProcessor
        assertGt(bridge.balanceOf(address(rollupProcessor)), 0);
        assertGt(tokens["LUSD"].erc.balanceOf(address(rollupProcessor)), 0);
    }

    function _repay() private {
        uint256 processorTBBalance = bridge.balanceOf(address(rollupProcessor));

        // Mint the borrower fee to ROLLUP_PROCESSOR in order to have a big enough balance for repaying
        // borrowerFee = processorTBBalance - processorLUSDBalance;
        deal(tokens["LUSD"].addr, address(rollupProcessor), processorTBBalance);

        rollupProcessor.convert(
            address(bridge),
            AztecTypes.AztecAsset(2, address(bridge), AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(1, tokens["LUSD"].addr, AztecTypes.AztecAssetType.ERC20),
            AztecTypes.AztecAsset(3, address(0), AztecTypes.AztecAssetType.ETH),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            processorTBBalance,
            1,
            MAX_FEE
        );

        // Check the bridge doesn't hold any ETH or LUSD
        assertEq(address(bridge).balance, 0);
        assertEq(tokens["LUSD"].erc.balanceOf(address(bridge)), 0);

        // I want to check whether withdrawn amount of ETH is the same as the ROLLUP_PROCESSOR_WEI_BALANCE.
        // There is some imprecision so the amount is allowed to be different by 1 wei.
        uint256 diffInETH = address(rollupProcessor).balance < ROLLUP_PROCESSOR_WEI_BALANCE
            ? ROLLUP_PROCESSOR_WEI_BALANCE - address(rollupProcessor).balance
            : address(rollupProcessor).balance - ROLLUP_PROCESSOR_WEI_BALANCE;
        assertLe(diffInETH, 1);
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

        Status troveStatus = Status(bridge.troveManager().getTroveStatus(address(bridge)));
        assertTrue(troveStatus == Status.closedByOwner);

        // Check the bridge doesn't hold any ETH or LUSD
        assertEq(address(bridge).balance, 0);
        assertEq(tokens["LUSD"].erc.balanceOf(address(bridge)), 0);

        // I want to check whether withdrawn amount of ETH is the same as the ROLLUP_PROCESSOR_WEI_BALANCE.
        // There is some imprecision so the amount is allowed to be different by 1 wei.
        uint256 diffInETH = OWNER.balance < OWNER_WEI_BALANCE
            ? OWNER_WEI_BALANCE - OWNER.balance
            : OWNER.balance - OWNER_WEI_BALANCE;
        assertLe(diffInETH, 1);

        // Check the TB total supply is 0
        assertEq(bridge.totalSupply(), 0);

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

        // Check that non-zero amount of ETH has been redeemed
        assertGt(address(rollupProcessor).balance, 0);
    }

    function _closeRedeem() private {
        // Set msg.sender to OWNER
        vm.startPrank(OWNER);

        bridge.closeTrove();

        // Check the bridge doesn't hold any ETH or LUSD
        assertEq(address(bridge).balance, 0);

        // Check that non-zero amount of ETH has been redeemed
        assertGt(OWNER.balance, 0);

        // Check the TB total supply is 0
        assertEq(bridge.totalSupply(), 0);

        vm.stopPrank();
    }

    receive() external payable {}

    // Here so that I can successfully liquidate a trove from within this contract.
    fallback() external payable {}
}
