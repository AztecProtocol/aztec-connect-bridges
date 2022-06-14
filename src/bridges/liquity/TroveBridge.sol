// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {IDefiBridge} from "../../aztec/interfaces/IDefiBridge.sol";
import {AztecTypes} from "../../aztec/AztecTypes.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";

import {IBorrowerOperations} from "./interfaces/IBorrowerOperations.sol";
import {ITroveManager} from "./interfaces/ITroveManager.sol";
import {ISortedTroves} from "./interfaces/ISortedTroves.sol";

/**
 * @title Aztec Connect Bridge for opening and closing Liquity's troves
 * @author Jan Benes (@benesjan on Github and Telegram)
 * @notice You can use this contract to borrow and repay LUSD
 * @dev The contract inherits from OpenZeppelin's implementation of ERC20 token because token balances are used to track
 * the depositor's ownership of the assets controlled by the bridge contract. The token is called TroveBridge and
 * the token symbol is TB-[initial ICR] (ICR is an acronym for individual collateral ratio). 1 TB token always
 * represents 1 LUSD worth of debt. In case the trove is not closed by redemption or liquidation, users can withdraw
 * their collateral by supplying TB and an equal amount of LUSD to the bridge. 1 deployment of the bridge contract
 * controls 1 trove. The bridge keeps precise accounting of debt by making sure that no user can change the trove's ICR.
 * This means that when a price goes down the only way how a user can avoid liquidation penalty is to repay their debt.
 *
 * In case the trove gets liquidated, the bridge no longer controls any ETH and all the TB balances are irrelevant.
 * At this point the bridge is defunct unless owner is the only one who borrowed. If owner is the only who borrowed
 * calling closeTrove() will succeed and owner's balance will get burned making TB total supply 0.
 *
 * If the trove is closed by redemption, users can withdraw their remaining collateral by supplying their TB.
 */
contract TroveBridge is ERC20, Ownable, IDefiBridge {
    using Strings for uint256;

    error NonZeroTotalSupply();
    error ApproveFailed(address token);
    error InvalidCaller();
    error IncorrectStatus(Status expected, Status received);
    error IncorrectInput();
    error OwnerNotLast();
    error TransferFailed();
    error AsyncModeDisabled();

    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;

    IBorrowerOperations public constant BORROWER_OPERATIONS =
        IBorrowerOperations(0x24179CD81c9e782A4096035f7eC97fB8B783e007);
    ITroveManager public constant TROVE_MANAGER = ITroveManager(0xA39739EF8b0231DbFA0DcdA07d7e29faAbCf4bb2);
    ISortedTroves public constant SORTED_TROVES = ISortedTroves(0x8FdD3fbFEb32b28fb73555518f8b361bCeA741A6);

    // The amount of dust to leave in the contract
    // Optimization based on EIP-1087
    uint256 public constant DUST = 1;

    address public immutable ROLLUP_PROCESSOR;
    uint256 public immutable INITIAL_ICR;

    // Used to check whether collateral has already been claimed during redemptions.
    bool private collateralClaimed;

    // Trove status taken from TroveManager.sol
    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation,
        closedByRedemption
    }

    /**
     * @notice Set the address of RollupProcessor.sol and initial ICR
     * @param _rollupProcessor Address of the RollupProcessor.sol
     * @param _initialICRPerc Collateral ratio denominated in percents to be used when opening the Trove
     */
    constructor(address _rollupProcessor, uint256 _initialICRPerc)
        ERC20("TroveBridge", string(abi.encodePacked("TB-", _initialICRPerc.toString())))
    {
        ROLLUP_PROCESSOR = _rollupProcessor;
        INITIAL_ICR = _initialICRPerc * 1e16;
        _mint(address(this), DUST);
    }

    receive() external payable {}

    fallback() external payable {}

    /**
     * @notice A function which opens the trove.
     * @param _upperHint Address of a Trove with a position in the sorted list before the correct insert position.
     * @param _lowerHint Address of a Trove with a position in the sorted list after the correct insert position.
     * See https://github.com/liquity/dev#supplying-hints-to-trove-operations for more details about hints.
     * @param _maxFee Maximum borrower fee.
     * @dev Sufficient amount of ETH has to be send so that at least 2000 LUSD gets borrowed. 2000 LUSD is a minimum
     * amount allowed by Liquity.
     */
    function openTrove(
        address _upperHint,
        address _lowerHint,
        uint256 _maxFee
    ) external payable onlyOwner {
        // Checks whether the trove can be safely opened/reopened
        if (this.totalSupply() != 0) revert NonZeroTotalSupply();

        if (!IERC20(LUSD).approve(ROLLUP_PROCESSOR, type(uint256).max)) revert ApproveFailed(LUSD);
        if (!this.approve(ROLLUP_PROCESSOR, type(uint256).max)) revert ApproveFailed(address(this));

        uint256 amtToBorrow = computeAmtToBorrow(msg.value);

        (uint256 debtBefore, , , ) = TROVE_MANAGER.getEntireDebtAndColl(address(this));
        BORROWER_OPERATIONS.openTrove{value: msg.value}(_maxFee, amtToBorrow, _upperHint, _lowerHint);
        (uint256 debtAfter, , , ) = TROVE_MANAGER.getEntireDebtAndColl(address(this));

        IERC20(LUSD).transfer(msg.sender, IERC20(LUSD).balanceOf(address(this)) - DUST);
        // I mint TB token to msg.sender to be able to track collateral ownership. Minted amount equals debt increase.
        _mint(msg.sender, debtAfter - debtBefore);
    }

    /**
     * @notice A function which stakes or unstakes LQTY to/from LQTYStaking.sol.
     * @dev This method can only be called from the RollupProcessor.sol. If the input asset is ETH, borrowing flow is
     * executed. If TB, repaying. RollupProcessor.sol has to transfer the tokens to the bridge before calling
     * the method. If this is not the case, the function will revert.
     *
     *                              Borrowing               Repaying                Redeeming
     * @param _inputAssetA -         ETH                     TB                      TB
     * @param _inputAssetB -         None                    LUSD                    None
     * @param _outputAssetA -        TB                      ETH                     ETH
     * @param _outputAssetB -        LUSD                    None                    None
     * @param _inputValue -          amount of ETH           amount of TB and LUSD   amount of TB
     * @param _interactionNonce -    nonce                   nonce                   nonce
     * @param _auxData -             max borrower fee        0                       0
     * @return outputValueA -       amount of TB            amount of ETH           amount of ETH
     * @return outputValueB -       amount of LUSD          0                       0
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata _inputAssetB,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata _outputAssetB,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64 _auxData,
        address
    )
        external
        payable
        override(IDefiBridge)
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool
        )
    {
        if (msg.sender != ROLLUP_PROCESSOR) revert InvalidCaller();
        Status troveStatus = Status(TROVE_MANAGER.getTroveStatus(address(this)));

        address upperHint = SORTED_TROVES.getPrev(address(this));
        address lowerHint = SORTED_TROVES.getNext(address(this));

        if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH &&
            _outputAssetA.erc20Address == address(this) &&
            _outputAssetB.erc20Address == LUSD
        ) {
            // Borrowing
            if (troveStatus != Status.active) revert IncorrectStatus(Status.active, troveStatus);
            // outputValueA = by how much debt will increase and how much TB to mint
            outputValueB = computeAmtToBorrow(_inputValue); // LUSD amount to borrow

            (uint256 debtBefore, , , ) = TROVE_MANAGER.getEntireDebtAndColl(address(this));
            BORROWER_OPERATIONS.adjustTrove{value: _inputValue}(_auxData, 0, outputValueB, true, upperHint, lowerHint);
            (uint256 debtAfter, , , ) = TROVE_MANAGER.getEntireDebtAndColl(address(this));

            // outputValueA = debt increase = amount of TB to mint
            outputValueA = debtAfter - debtBefore;
            _mint(address(this), outputValueA);
        } else if (
            _inputAssetA.erc20Address == address(this) &&
            _inputAssetB.erc20Address == LUSD &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.ETH
        ) {
            // Repaying
            if (troveStatus != Status.active) revert IncorrectStatus(Status.active, troveStatus);
            (, uint256 coll, , ) = TROVE_MANAGER.getEntireDebtAndColl(address(this));
            outputValueA = (coll * _inputValue) / this.totalSupply(); // Amount of collateral to withdraw
            BORROWER_OPERATIONS.adjustTrove(0, outputValueA, _inputValue, false, upperHint, lowerHint);
            _burn(address(this), _inputValue);
            IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(_interactionNonce);
        } else if (
            _inputAssetA.erc20Address == address(this) && _outputAssetA.assetType == AztecTypes.AztecAssetType.ETH
        ) {
            // Redeeming
            if (troveStatus != Status.closedByRedemption)
                revert IncorrectStatus(Status.closedByRedemption, troveStatus);
            if (!collateralClaimed) {
                BORROWER_OPERATIONS.claimCollateral();
                collateralClaimed = true;
            }
            outputValueA = (address(this).balance * _inputValue) / this.totalSupply();
            _burn(address(this), _inputValue);
            IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(_interactionNonce);
        } else {
            revert IncorrectInput();
        }
    }

    /**
     * @notice A function which closes the trove.
     * @dev LUSD allowance has to be at least (remaining debt - 200).
     */
    function closeTrove() external onlyOwner {
        address payable owner = payable(owner());
        uint256 ownerTBBalance = balanceOf(owner);
        if (ownerTBBalance != totalSupply()) revert OwnerNotLast();

        _burn(owner, ownerTBBalance);

        Status troveStatus = Status(TROVE_MANAGER.getTroveStatus(address(this)));
        if (troveStatus == Status.active) {
            (uint256 remainingDebt, , , ) = TROVE_MANAGER.getEntireDebtAndColl(address(this));
            // 200e18 is a part of debt which gets repaid from LUSD_GAS_COMPENSATION.
            if (!IERC20(LUSD).transferFrom(owner, address(this), remainingDebt - 200e18)) revert TransferFailed();
            BORROWER_OPERATIONS.closeTrove();
        } else if (troveStatus == Status.closedByRedemption) {
            if (!collateralClaimed) {
                BORROWER_OPERATIONS.claimCollateral();
            } else {
                collateralClaimed = false;
            }
        }

        owner.transfer(address(this).balance);
    }

    // @notice This function always reverts because this contract does not implement async flow.
    function finalise(
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        uint256,
        uint64
    )
        external
        payable
        override(IDefiBridge)
        returns (
            uint256,
            uint256,
            bool
        )
    {
        revert AsyncModeDisabled();
    }

    /**
     * @notice Compute how much LUSD to borrow against collateral in order to keep ICR constant and by how much total
     * trove debt will increase.
     * @param _collateral Amount of ETH denominated in Wei
     * @return amtToBorrow Amount of LUSD to borrow to keep ICR constant.
     * + borrowing fee)
     * @dev I don't use view modifier here because the function updates PriceFeed state.
     *
     * Since the Trove opening and adjustment processes have desired amount of LUSD to borrow on the input and not
     * the desired ICR I have to do the computation of borrowing fee "backwards". Here are the operations I did in order
     * to get the final formula:
     *      1) debtIncrease = amtToBorrow + amtToBorrow * BORROWING_RATE / DECIMAL_PRECISION + 200LUSD
     *      2) debtIncrease - 200LUSD = amtToBorrow * (1 + BORROWING_RATE / DECIMAL_PRECISION)
     *      3) amtToBorrow = (debtIncrease - 200LUSD) / (1 + BORROWING_RATE / DECIMAL_PRECISION)
     *      4) amtToBorrow = (debtIncrease - 200LUSD) * DECIMAL_PRECISION / (DECIMAL_PRECISION + BORROWING_RATE)
     * Note1: For trove adjustments (not opening) remove the 200 LUSD fee compensation from the formulas above.
     * Note2: Step 4 is necessary to avoid loss of precision. BORROWING_RATE / DECIMAL_PRECISION was rounded to 0.
     * Note3: The borrowing fee computation is on this line in Liquity code: https://github.com/liquity/dev/blob/cb583ddf5e7de6010e196cfe706bd0ca816ea40e/packages/contracts/contracts/TroveManager.sol#L1433
     */
    function computeAmtToBorrow(uint256 _collateral) public returns (uint256 amtToBorrow) {
        uint256 price = TROVE_MANAGER.priceFeed().fetchPrice();
        bool isRecoveryMode = TROVE_MANAGER.checkRecoveryMode(price);
        if (TROVE_MANAGER.getTroveStatus(address(this)) == 1) {
            // Trove is active - use current ICR and not the initial one
            uint256 icr = TROVE_MANAGER.getCurrentICR(address(this), price);
            amtToBorrow = (_collateral * price) / icr;
            if (!isRecoveryMode) {
                // Liquity is not in recovery mode so borrowing fee applies
                uint256 borrowingRate = TROVE_MANAGER.getBorrowingRateWithDecay();
                amtToBorrow = (amtToBorrow * 1e18) / (borrowingRate + 1e18);
            }
        } else {
            // Trove is inactive - I will use initial ICR to compute debt
            // 200e18 - 200 LUSD gas compensation to liquidators
            amtToBorrow = (_collateral * price) / INITIAL_ICR - 200e18;
            if (!isRecoveryMode) {
                // Liquity is not in recovery mode so borrowing fee applies
                uint256 borrowingRate = TROVE_MANAGER.getBorrowingRateWithDecay();
                amtToBorrow = (amtToBorrow * 1e18) / (borrowingRate + 1e18);
            }
        }
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view override(ERC20) returns (uint256) {
        return super.totalSupply() - DUST;
    }
}
