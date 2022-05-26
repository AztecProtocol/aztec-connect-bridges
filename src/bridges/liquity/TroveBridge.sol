// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4 <=0.8.10;
import '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Strings.sol';
import '../../interfaces/IDefiBridge.sol';
import '../../interfaces/IRollupProcessor.sol';
import './interfaces/IBorrowerOperations.sol';
import './interfaces/ITroveManager.sol';
import './interfaces/ISortedTroves.sol';

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

    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;

    IBorrowerOperations public constant operations = IBorrowerOperations(0x24179CD81c9e782A4096035f7eC97fB8B783e007);
    ITroveManager public constant troveManager = ITroveManager(0xA39739EF8b0231DbFA0DcdA07d7e29faAbCf4bb2);
    ISortedTroves public constant sortedTroves = ISortedTroves(0x8FdD3fbFEb32b28fb73555518f8b361bCeA741A6);

    address public immutable processor;
    uint256 public immutable initialICR;

    // Used to check whether collateral has already been claimed during redemptions.
    bool private _collateralClaimed;

    // Trove status taken from TroveManager.sol
    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation,
        closedByRedemption
    }

    error NonZeroTotalSupply();
    error ApproveFailed(address token);
    error InvalidCaller();
    error IncorrectStatus(Status expected, Status received);
    error IncorrectInput();
    error OwnerNotLast();
    error TransferFailed();
    error AsyncModeDisabled();

    /**
     * @notice Set the address of RollupProcessor.sol and initial ICR
     * @param _processor Address of the RollupProcessor.sol
     * @param _initialICRPerc Collateral ratio denominated in percents to be used when opening the Trove
     */
    constructor(address _processor, uint256 _initialICRPerc)
        ERC20('TroveBridge', string(abi.encodePacked('TB-', _initialICRPerc.toString())))
    {
        processor = _processor;
        initialICR = _initialICRPerc * 1e16;
    }

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

        if (!IERC20(LUSD).approve(processor, type(uint256).max)) revert ApproveFailed(LUSD);
        if (!this.approve(processor, type(uint256).max)) revert ApproveFailed(address(this));

        uint256 amtToBorrow = computeAmtToBorrow(msg.value);

        (uint256 debtBefore, , , ) = troveManager.getEntireDebtAndColl(address(this));
        operations.openTrove{value: msg.value}(_maxFee, amtToBorrow, _upperHint, _lowerHint);
        (uint256 debtAfter, , , ) = troveManager.getEntireDebtAndColl(address(this));

        IERC20(LUSD).transfer(msg.sender, IERC20(LUSD).balanceOf(address(this)));
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
     * @param inputAssetA -         ETH                     TB                      TB
     * @param inputAssetB -         None                    LUSD                    None
     * @param outputAssetA -        TB                      ETH                     ETH
     * @param outputAssetB -        LUSD                    None                    None
     * @param inputValue -          amount of ETH           amount of TB and LUSD   amount of TB
     * @param interactionNonce -    nonce                   nonce                   nonce
     * @param auxData -             max borrower fee        0                       0
     * @return outputValueA -       amount of TB            amount of ETH           amount of ETH
     * @return outputValueB -       amount of LUSD          0                       0
     */
    function convert(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata inputAssetB,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata outputAssetB,
        uint256 inputValue,
        uint256 interactionNonce,
        uint64 auxData,
        address
    )
        external
        payable
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool
        )
    {
        if (msg.sender != processor) revert InvalidCaller();
        Status troveStatus = Status(troveManager.getTroveStatus(address(this)));

        address upperHint = sortedTroves.getPrev(address(this));
        address lowerHint = sortedTroves.getNext(address(this));

        if (
            inputAssetA.assetType == AztecTypes.AztecAssetType.ETH &&
            outputAssetA.erc20Address == address(this) &&
            outputAssetB.erc20Address == LUSD
        ) {
            // Borrowing
            if (troveStatus != Status.active) revert IncorrectStatus(Status.active, troveStatus);
            // outputValueA = by how much debt will increase and how much TB to mint
            outputValueB = computeAmtToBorrow(inputValue); // LUSD amount to borrow

            (uint256 debtBefore, , , ) = troveManager.getEntireDebtAndColl(address(this));
            operations.adjustTrove{value: inputValue}(auxData, 0, outputValueB, true, upperHint, lowerHint);
            (uint256 debtAfter, , , ) = troveManager.getEntireDebtAndColl(address(this));

            // outputValueA = debt increase = amount of TB to mint
            outputValueA = debtAfter - debtBefore;
            _mint(address(this), outputValueA);
        } else if (
            inputAssetA.erc20Address == address(this) &&
            inputAssetB.erc20Address == LUSD &&
            outputAssetA.assetType == AztecTypes.AztecAssetType.ETH
        ) {
            // Repaying
            if (troveStatus != Status.active) revert IncorrectStatus(Status.active, troveStatus);
            (, uint256 coll, , ) = troveManager.getEntireDebtAndColl(address(this));
            outputValueA = (coll * inputValue) / this.totalSupply(); // Amount of collateral to withdraw
            operations.adjustTrove(0, outputValueA, inputValue, false, upperHint, lowerHint);
            _burn(address(this), inputValue);
            IRollupProcessor(processor).receiveEthFromBridge{value: outputValueA}(interactionNonce);
        } else if (
            inputAssetA.erc20Address == address(this) && outputAssetA.assetType == AztecTypes.AztecAssetType.ETH
        ) {
            // Redeeming
            if (troveStatus != Status.closedByRedemption)
                revert IncorrectStatus(Status.closedByRedemption, troveStatus);
            if (!_collateralClaimed) {
                operations.claimCollateral();
                _collateralClaimed = true;
            }
            outputValueA = (address(this).balance * inputValue) / this.totalSupply();
            _burn(address(this), inputValue);
            IRollupProcessor(processor).receiveEthFromBridge{value: outputValueA}(interactionNonce);
        } else {
            revert IncorrectInput();
        }
    }

    /**
     * @notice A function which closes the trove.
     * @dev LUSD allowance has to be at least (remaining debt - 200).
     */
    function closeTrove() public onlyOwner {
        address payable owner = payable(owner());
        uint256 ownerTBBalance = balanceOf(owner);
        if (ownerTBBalance != totalSupply()) revert OwnerNotLast();

        _burn(owner, ownerTBBalance);

        Status troveStatus = Status(troveManager.getTroveStatus(address(this)));
        if (troveStatus == Status.active) {
            (uint256 remainingDebt, , , ) = troveManager.getEntireDebtAndColl(address(this));
            // 200e18 is a part of debt which gets repaid from LUSD_GAS_COMPENSATION.
            if (!IERC20(LUSD).transferFrom(owner, address(this), remainingDebt - 200e18)) revert TransferFailed();
            operations.closeTrove();
        } else if (troveStatus == Status.closedByRedemption) {
            if (!_collateralClaimed) {
                operations.claimCollateral();
            } else {
                _collateralClaimed = false;
            }
        }

        owner.transfer(address(this).balance);
    }

    /**
     * @notice Compute how much LUSD to borrow against collateral in order to keep ICR constant and by how much total
     * trove debt will increase.
     * @param _coll Amount of ETH denominated in Wei
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
    function computeAmtToBorrow(uint256 _coll) public returns (uint256 amtToBorrow) {
        uint256 price = troveManager.priceFeed().fetchPrice();
        bool isRecoveryMode = troveManager.checkRecoveryMode(price);
        if (troveManager.getTroveStatus(address(this)) == 1) {
            // Trove is active - use current ICR and not the initial one
            uint256 icr = troveManager.getCurrentICR(address(this), price);
            amtToBorrow = (_coll * price) / icr;
            if (!isRecoveryMode) {
                // Liquity is not in recovery mode so borrowing fee applies
                uint256 borrowingRate = troveManager.getBorrowingRateWithDecay();
                amtToBorrow = (amtToBorrow * 1e18) / (borrowingRate + 1e18);
            }
        } else {
            // Trove is inactive - I will use initial ICR to compute debt
            // 200e18 - 200 LUSD gas compensation to liquidators
            amtToBorrow = (_coll * price) / initialICR - 200e18;
            if (!isRecoveryMode) {
                // Liquity is not in recovery mode so borrowing fee applies
                uint256 borrowingRate = troveManager.getBorrowingRateWithDecay();
                amtToBorrow = (amtToBorrow * 1e18) / (borrowingRate + 1e18);
            }
        }
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
        returns (
            uint256,
            uint256,
            bool
        )
    {
        revert AsyncModeDisabled();
    }

    receive() external payable {}

    fallback() external payable {}
}
