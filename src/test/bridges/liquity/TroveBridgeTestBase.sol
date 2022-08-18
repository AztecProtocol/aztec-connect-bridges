// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {TroveBridge} from "../../../bridges/liquity/TroveBridge.sol";
import {IBorrowerOperations} from "../../../interfaces/liquity/IBorrowerOperations.sol";
import {ITroveManager} from "../../../interfaces/liquity/ITroveManager.sol";
import {ISortedTroves} from "../../../interfaces/liquity/ISortedTroves.sol";
import {IHintHelpers} from "../../../interfaces/liquity/IHintHelpers.sol";

import {TestUtil} from "./utils/TestUtil.sol";

contract TroveBridgeTestBase is TestUtil {
    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation,
        closedByRedemption
    }

    IHintHelpers internal constant HINT_HELPERS = IHintHelpers(0xE84251b93D9524E0d2e621Ba7dc7cb3579F997C0);
    address internal constant STABILITY_POOL = 0x66017D22b0f8556afDd19FC67041899Eb65a21bb;
    address internal constant LQTY_STAKING_CONTRACT = 0x4f9Fbb3f1E99B56e0Fe2892e623Ed36A76Fc605d;
    IBorrowerOperations public constant BORROWER_OPERATIONS =
        IBorrowerOperations(0x24179CD81c9e782A4096035f7eC97fB8B783e007);
    ITroveManager public constant TROVE_MANAGER = ITroveManager(0xA39739EF8b0231DbFA0DcdA07d7e29faAbCf4bb2);
    ISortedTroves internal constant SORTED_TROVES = ISortedTroves(0x8FdD3fbFEb32b28fb73555518f8b361bCeA741A6);

    address internal constant OWNER = address(24);

    uint256 internal constant OWNER_ETH_BALANCE = 50 ether;
    uint256 internal constant ROLLUP_PROCESSOR_ETH_BALANCE = 1 ether;

    uint64 internal constant MAX_FEE = 5e16; // Slippage protection: 5%
    uint256 public constant MCR = 1100000000000000000; // 110%
    uint256 public constant CCR = 1500000000000000000; // 150%

    // From LiquityMath.sol
    uint256 internal constant NICR_PRECISION = 1e20;

    TroveBridge internal bridge;

    receive() external payable {}

    // Here so that I can successfully liquidate a trove from within this contract.
    fallback() external payable {}

    function _baseSetUp() internal {
        _setUpTokensAndLabels();

        vm.label(address(bridge.USDC()), "USDC");
        vm.label(address(BORROWER_OPERATIONS), "BORROWER_OPERATIONS");
        vm.label(address(TROVE_MANAGER), "TROVE_MANAGER");
        vm.label(address(SORTED_TROVES), "SORTED_TROVES");
        vm.label(address(bridge.LUSD_USDC_POOL()), "LUSD_USDC_POOL");
        vm.label(address(bridge.USDC_ETH_POOL()), "USDC_ETH_POOL");
        vm.label(address(LIQUITY_PRICE_FEED), "LIQUITY_PRICE_FEED");
        vm.label(STABILITY_POOL, "STABILITY_POOL");
        vm.label(LQTY_STAKING_CONTRACT, "LQTY_STAKING_CONTRACT");

        // Set LUSD bridge balance to 1 WEI
        // Necessary for the optimization based on EIP-1087 to work!
        deal(tokens["LUSD"].addr, address(bridge), 1);
    }

    function _openTrove() internal {
        // Set owner's balance
        vm.deal(OWNER, OWNER_ETH_BALANCE);

        // Set msg.sender to OWNER
        vm.startPrank(OWNER);

        uint256 amtToBorrow = bridge.computeAmtToBorrow(OWNER_ETH_BALANCE);
        uint256 nicr = (OWNER_ETH_BALANCE * NICR_PRECISION) / amtToBorrow;

        // The following is Solidity implementation of https://github.com/liquity/dev#opening-a-trove
        uint256 numTrials = 15;
        uint256 randomSeed = 42;
        (address approxHint, , ) = HINT_HELPERS.getApproxHint(nicr, numTrials, randomSeed);
        (address upperHint, address lowerHint) = SORTED_TROVES.findInsertPosition(nicr, approxHint, approxHint);

        // Open the trove
        bridge.openTrove{value: OWNER_ETH_BALANCE}(upperHint, lowerHint, MAX_FEE);

        uint256 price = TROVE_MANAGER.priceFeed().fetchPrice();
        uint256 icr = TROVE_MANAGER.getCurrentICR(address(bridge), price);
        assertEq(icr, bridge.INITIAL_ICR(), "ICR doesn't equal initial ICR");

        (uint256 debtAfterBorrowing, uint256 collAfterBorrowing, , ) = TROVE_MANAGER.getEntireDebtAndColl(
            address(bridge)
        );
        assertEq(bridge.totalSupply(), debtAfterBorrowing, "TB total supply doesn't equal totalDebt");
        assertEq(collAfterBorrowing, OWNER_ETH_BALANCE, "Trove's collateral doesn't equal deposit amount");

        uint256 lusdBalance = tokens["LUSD"].erc.balanceOf(OWNER);
        assertApproxEqAbs(lusdBalance, amtToBorrow, 1, "Borrowed amount differs from received by more than 1 wei");

        assertEq(address(bridge).balance, 0, "Bridge holds ETH after trove opening");
        assertEq(tokens["LUSD"].erc.balanceOf(address(bridge)), bridge.DUST(), "Bridge holds LUSD after trove opening");

        vm.stopPrank();
    }

    function _closeTrove() internal {
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

        Status troveStatus = Status(TROVE_MANAGER.getTroveStatus(address(bridge)));
        assertTrue(troveStatus == Status.closedByOwner, "Invalid trove status");

        assertEq(address(bridge).balance, 0, "Bridge holds ETH after trove closure");
        assertEq(tokens["LUSD"].erc.balanceOf(address(bridge)), bridge.DUST(), "Bridge holds LUSD after trove closure");

        assertApproxEqAbs(
            OWNER.balance,
            OWNER_ETH_BALANCE,
            1,
            "Current owner balance differs from the initial balance by more than 1 wei"
        );

        assertEq(bridge.totalSupply(), 0, "TB total supply is not 0 after trove closure");

        vm.stopPrank();
    }

    function _closeTroveAfterRedistribution(uint256 _expectedBalance) internal {
        // Set msg.sender to OWNER
        vm.startPrank(OWNER);

        (uint256 debtBeforeClosure, , , ) = TROVE_MANAGER.getEntireDebtAndColl(address(bridge));

        uint256 amountToRepay = debtBeforeClosure - 200e18;

        // Increase OWNER's LUSD balance by borrowerFee
        deal(tokens["LUSD"].addr, OWNER, amountToRepay);
        tokens["LUSD"].erc.approve(address(bridge), amountToRepay);

        bridge.closeTrove();

        Status troveStatus = Status(TROVE_MANAGER.getTroveStatus(address(bridge)));
        assertTrue(troveStatus == Status.closedByOwner, "Invalid trove status");

        assertEq(address(bridge).balance, 0, "Bridge holds ETH after trove closure");
        assertEq(tokens["LUSD"].erc.balanceOf(address(bridge)), bridge.DUST(), "Bridge holds LUSD after trove closure");

        assertApproxEqAbs(
            OWNER.balance,
            _expectedBalance,
            2e17,
            "Current owner balance differs from the initial balance by more than 0.2 ETH"
        );

        assertEq(bridge.totalSupply(), 0, "TB total supply is not 0 after trove closure");

        vm.stopPrank();
    }

    function _closeRedeem() internal {
        // Set msg.sender to OWNER
        vm.startPrank(OWNER);

        bridge.closeTrove();

        assertEq(address(bridge).balance, 0, "Bridge holds ETH after trove closing");

        assertGt(OWNER.balance, 0, "No ETH has been redeemed");

        assertEq(bridge.totalSupply(), 0, "TB total supply is not 0");

        vm.stopPrank();
    }
}
