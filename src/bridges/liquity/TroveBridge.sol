// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {IRollupProcessor} from "rollup-encoder/interfaces/IRollupProcessor.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {IWETH} from "../../interfaces/IWETH.sol";
import {IBorrowerOperations} from "../../interfaces/liquity/IBorrowerOperations.sol";
import {ITroveManager} from "../../interfaces/liquity/ITroveManager.sol";
import {ISortedTroves} from "../../interfaces/liquity/ISortedTroves.sol";
import {IUniswapV3SwapCallback} from "../../interfaces/uniswapv3/callback/IUniswapV3SwapCallback.sol";
import {IUniswapV3PoolActions} from "../../interfaces/uniswapv3/pool/IUniswapV3PoolActions.sol";

/**
 * @title Aztec Connect Bridge for opening and closing Liquity's troves
 * @author Jan Benes (@benesjan on Github and Telegram)
 * @notice You can use this contract to borrow and repay LUSD
 * @dev The contract inherits from OpenZeppelin's implementation of ERC20 token because token balances are used to track
 * the depositor's ownership of the assets controlled by the bridge contract. The token is called TroveBridge and
 * the token symbol is TB-[initial ICR] (ICR is an acronym for individual collateral ratio). 1 TB token represents
 * 1 LUSD worth of debt if no redistribution took place (Liquity whitepaper section 4.2). If redistribution took place
 * 1 TB corresponds to more than 1 LUSD. In case the trove is not closed by redemption or liquidation, users can
 * withdraw their collateral by supplying TB and an equal amount of LUSD to the bridge. Alternatively, they supply only
 * TB on input in which case their debt will be repaid with a part their collateral. In case a user supplies both TB and
 * LUSD on input and 1 TB corresponds to more than 1 LUSD part of the ETH collateral withdrawn is swapped to LUSD and
 * the output amount is repaid. This swap is necessary because it's impossible to provide different amounts of
 * _inputAssetA and _inputAssetB. 1 deployment of the bridge contract controls 1 trove. The bridge keeps precise
 * accounting of debt by making sure that no user can change the trove's ICR. This means that when a price goes down
 * the only way how a user can avoid liquidation penalty is to repay their debt.
 *
 * In case the trove gets liquidated, the bridge no longer controls any ETH and all the TB balances are irrelevant.
 * At this point the bridge is defunct (unless owner is the only one who borrowed). If owner is the only who borrowed
 * calling closeTrove() will succeed and owner's balance will get burned, making TB total supply 0.
 *
 * If the trove is closed by redemption, users can withdraw their remaining collateral by supplying their TB.
 *
 * DISCLAIMER: Users are not able to exit the Trove in case the Liquity system is in recovery mode (total CR < 150%).
 * This is because in recovery mode only pure collateral top-up or debt repayment is allowed. This makes exit
 * from this bridge impossible in recovery mode because such exit is always a combination of debt repayment and
 * collateral withdrawal.
 */
contract TroveBridge is BridgeBase, ERC20, Ownable, IUniswapV3SwapCallback {
    using Strings for uint256;

    error NonZeroTotalSupply();
    error InvalidStatus(Status status);
    error InvalidDeltaAmounts();
    error OwnerNotLast();
    error MaxCostExceeded();
    error SwapFailed();

    // Trove status taken from TroveManager.sol
    enum Status {
        nonExistent,
        active,
        closedByOwner,
        closedByLiquidation,
        closedByRedemption
    }

    struct SwapCallbackData {
        uint256 debtToRepay;
        uint256 collToWithdraw;
    }

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;

    IBorrowerOperations public constant BORROWER_OPERATIONS =
        IBorrowerOperations(0x24179CD81c9e782A4096035f7eC97fB8B783e007);
    ITroveManager public constant TROVE_MANAGER = ITroveManager(0xA39739EF8b0231DbFA0DcdA07d7e29faAbCf4bb2);
    ISortedTroves public constant SORTED_TROVES = ISortedTroves(0x8FdD3fbFEb32b28fb73555518f8b361bCeA741A6);

    // Both pools are Uniswap V3 500 bps fee tier pools
    address public constant LUSD_USDC_POOL = 0x4e0924d3a751bE199C426d52fb1f2337fa96f736;
    address public constant USDC_ETH_POOL = 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640;

    // The amount of dust to leave in the contract
    // Optimization based on EIP-1087
    uint256 public constant DUST = 1;

    uint256 public immutable INITIAL_ICR;

    // Price precision
    uint256 public constant PRECISION = 1e18;

    // We are not setting price impact protection and in both swaps zeroForOne is false so sqrtPriceLimitX96
    // is set to TickMath.MAX_SQRT_RATIO - 1 = 1461446703485210103287273052203988822378723970341
    // See https://github.com/Uniswap/v3-periphery/blob/22a7ead071fff53f00d9ddc13434f285f4ed5c7d/contracts/SwapRouter.sol#L187
    // for more information.
    uint160 private constant SQRT_PRICE_LIMIT_X96 = 1461446703485210103287273052203988822378723970341;

    // Used to check whether collateral has already been claimed during redemptions.
    bool private collateralClaimed;

    /**
     * @notice Set the address of RollupProcessor.sol and initial ICR
     * @param _rollupProcessor Address of the RollupProcessor.sol
     * @param _initialICRPerc Collateral ratio denominated in percents to be used when opening the Trove
     */
    constructor(address _rollupProcessor, uint256 _initialICRPerc)
        BridgeBase(_rollupProcessor)
        ERC20("TroveBridge", string(abi.encodePacked("TB-", _initialICRPerc.toString())))
    {
        INITIAL_ICR = _initialICRPerc * 1e16;
        _mint(address(this), DUST);

        // Registering the bridge for subsidy
        uint256[] memory criteria = new uint256[](2);
        uint32[] memory gasUsage = new uint32[](2);
        uint32[] memory minGasPerMinute = new uint32[](2);

        criteria[0] = 0; // Borrow flow
        criteria[1] = 1; // Repay/redeem flow

        gasUsage[0] = 520000;
        gasUsage[1] = 410000;

        // This is approximately 520k / (24 * 60) / 2 --> targeting 1 full subsidized call per 2 days
        minGasPerMinute[0] = 180;

        // This is approximately 410k / (24 * 60) / 4 --> targeting 1 full subsidized call per 4 days
        minGasPerMinute[1] = 70;

        // We set gas usage and minGasPerMinute in the Subsidy contract
        SUBSIDY.setGasUsageAndMinGasPerMinute(criteria, gasUsage, minGasPerMinute);
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
    function openTrove(address _upperHint, address _lowerHint, uint256 _maxFee) external payable onlyOwner {
        // Checks whether the trove can be safely opened/reopened
        if (totalSupply() != 0) revert NonZeroTotalSupply();

        if (!IERC20(LUSD).approve(ROLLUP_PROCESSOR, type(uint256).max)) revert ErrorLib.ApproveFailed(LUSD);
        if (!this.approve(ROLLUP_PROCESSOR, type(uint256).max)) revert ErrorLib.ApproveFailed(address(this));

        uint256 amtToBorrow = computeAmtToBorrow(msg.value);

        (uint256 debtBefore,,,) = TROVE_MANAGER.getEntireDebtAndColl(address(this));
        BORROWER_OPERATIONS.openTrove{value: msg.value}(_maxFee, amtToBorrow, _upperHint, _lowerHint);
        (uint256 debtAfter,,,) = TROVE_MANAGER.getEntireDebtAndColl(address(this));

        IERC20(LUSD).transfer(msg.sender, IERC20(LUSD).balanceOf(address(this)) - DUST);
        // I mint TB token to msg.sender to be able to track collateral ownership. Minted amount equals debt increase.
        _mint(msg.sender, debtAfter - debtBefore);
    }

    /**
     * @notice A function which allows interaction with this bridge's trove from within Aztec Connect.
     * @dev This method can only be called from the RollupProcessor.sol. If the input asset is ETH, borrowing flow is
     * executed. If TB, repaying. RollupProcessor.sol has to transfer the tokens to the bridge before calling
     * the method. If this is not the case, the function will revert.
     *
     *                            Borrowing        | Repaying        | Repaying (redis.)| Repay. (coll.)| Redeeming
     * @param _inputAssetA -      ETH              | TB              | TB               | TB            | TB
     * @param _inputAssetB -      None             | LUSD            | LUSD             | None          | None
     * @param _outputAssetA -     TB               | ETH             | ETH              | ETH           | ETH
     * @param _outputAssetB -     LUSD             | LUSD            | TB               | None          | None
     * @param _totalInputValue -  ETH amount       | TB and LUSD amt.| TB and LUSD amt. | TB amount     | TB amount
     * @param _interactionNonce - nonce            | nonce           | nonce            | nonce         | nonce
     * @param _auxData -          max borrower fee | 0               | max price        | max price     | 0
     * @param _rollupBeneficiary - Address which receives subsidy if the call is eligible for it
     * @return outputValueA -     TB amount        | ETH amount      | ETH amount       | ETH amount    | ETH amount
     * @return outputValueB -     LUSD amount      | LUSD amount     | TB amount        | 0             | 0
     * @dev The amount of LUSD returned (outputValueB) during repayment will be non-zero only when the trove was
     * partially redeemed.
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata _inputAssetB,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata _outputAssetB,
        uint256 _totalInputValue,
        uint256 _interactionNonce,
        uint64 _auxData,
        address _rollupBeneficiary
    ) external payable override(BridgeBase) onlyRollup returns (uint256 outputValueA, uint256 outputValueB, bool) {
        Status troveStatus = Status(TROVE_MANAGER.getTroveStatus(address(this)));

        uint256 subsidyCriteria;

        if (
            _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH
                && _inputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED
                && _outputAssetA.erc20Address == address(this) && _outputAssetB.erc20Address == LUSD
        ) {
            // Borrowing
            if (troveStatus != Status.active) revert InvalidStatus(troveStatus);
            (outputValueA, outputValueB) = _borrow(_totalInputValue, _auxData);
            subsidyCriteria = 0;
        } else if (
            _inputAssetA.erc20Address == address(this) && _inputAssetB.erc20Address == LUSD
                && _outputAssetA.assetType == AztecTypes.AztecAssetType.ETH
        ) {
            // Repaying
            if (troveStatus != Status.active) revert InvalidStatus(troveStatus);
            if (_outputAssetB.erc20Address == LUSD) {
                // A case when the trove was partially redeemed (1 TB corresponding to less than 1 LUSD of debt) or not
                // redeemed and not touched by redistribution (1 TB corresponding to exactly 1 LUSD of debt)
                (outputValueA, outputValueB) = _repay(_totalInputValue, _interactionNonce);
            } else if (_outputAssetB.erc20Address == address(this)) {
                // A case when the trove was touched by redistribution (1 TB corresponding to more than 1 LUSD of
                // debt). For this reason it was impossible to provide enough LUSD on input since it's not currently
                // allowed to have different input token amounts. Swap part of the collateral to be able to repay
                // the debt in full.
                (outputValueA, outputValueB) = _repayWithCollateral(_totalInputValue, _auxData, _interactionNonce, true);
            } else {
                revert ErrorLib.InvalidOutputB();
            }
            subsidyCriteria = 1;
        } else if (
            _inputAssetA.erc20Address == address(this) && _inputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED
                && _outputAssetA.assetType == AztecTypes.AztecAssetType.ETH
                && _outputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED
        ) {
            if (troveStatus == Status.active) {
                // Repaying debt with collateral (using flash swaps)
                (outputValueA,) = _repayWithCollateral(_totalInputValue, _auxData, _interactionNonce, false);
            } else if (troveStatus == Status.closedByRedemption || troveStatus == Status.closedByLiquidation) {
                // Redeeming remaining collateral after the Trove is closed
                outputValueA = _redeem(_totalInputValue, _interactionNonce);
            } else {
                revert InvalidStatus(troveStatus);
            }
            subsidyCriteria = 1;
        } else {
            revert ErrorLib.InvalidInput();
        }

        SUBSIDY.claimSubsidy(subsidyCriteria, _rollupBeneficiary);
    }

    /**
     * @notice A function which closes the trove.
     * @dev LUSD allowance has to be at least (remaining debt - 200 LUSD).
     */
    function closeTrove() external onlyOwner {
        address payable owner = payable(owner());
        uint256 ownerTBBalance = balanceOf(owner);
        if (ownerTBBalance != totalSupply()) revert OwnerNotLast();

        _burn(owner, ownerTBBalance);

        Status troveStatus = Status(TROVE_MANAGER.getTroveStatus(address(this)));
        if (troveStatus == Status.active) {
            (uint256 remainingDebt,,,) = TROVE_MANAGER.getEntireDebtAndColl(address(this));
            // 200e18 is a part of debt which gets repaid from LUSD_GAS_COMPENSATION.
            if (!IERC20(LUSD).transferFrom(owner, address(this), remainingDebt - 200e18)) {
                revert ErrorLib.TransferFailed(LUSD);
            }
            BORROWER_OPERATIONS.closeTrove();
        } else if (troveStatus == Status.closedByRedemption || troveStatus == Status.closedByLiquidation) {
            if (!collateralClaimed) {
                BORROWER_OPERATIONS.claimCollateral();
            } else {
                collateralClaimed = false;
            }
        }

        owner.transfer(address(this).balance);
    }

    // @inheritdoc IUniswapV3SwapCallback
    // @dev See _repayWithCollateral(...) method for more information about how this callback is entered.
    function uniswapV3SwapCallback(int256 _amount0Delta, int256 _amount1Delta, bytes calldata _data)
        external
        override(IUniswapV3SwapCallback)
    {
        // Swaps entirely within 0-liquidity regions are not supported
        if (_amount0Delta <= 0 && _amount1Delta <= 0) revert InvalidDeltaAmounts();
        // Uniswap pools always call callback on msg.sender so this check is enough to prevent malicious behavior
        if (msg.sender == LUSD_USDC_POOL) {
            SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
            // Repay debt in full
            (address upperHint, address lowerHint) = _getHints();
            BORROWER_OPERATIONS.adjustTrove(0, data.collToWithdraw, data.debtToRepay, false, upperHint, lowerHint);

            // Pay LUSD_USDC_POOL for the swap by passing it as a recipient to the next swap (WETH -> USDC)
            IUniswapV3PoolActions(USDC_ETH_POOL).swap(
                LUSD_USDC_POOL, // recipient
                false, // zeroForOne
                -_amount1Delta, // amount of USDC to pay to LUSD_USDC_POOL for the swap
                SQRT_PRICE_LIMIT_X96,
                ""
            );
        } else if (msg.sender == USDC_ETH_POOL) {
            // Pay USDC_ETH_POOL for the USDC
            uint256 amountToPay = uint256(_amount1Delta);
            IWETH(WETH).deposit{value: amountToPay}(); // wrap only what is needed to pay
            IWETH(WETH).transfer(address(USDC_ETH_POOL), amountToPay);
        } else {
            revert ErrorLib.InvalidCaller();
        }
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
        if (TROVE_MANAGER.getTroveStatus(address(this)) == 1) {
            // Trove is active - use current ICR and not the initial one
            uint256 icr = TROVE_MANAGER.getCurrentICR(address(this), price);
            amtToBorrow = (_collateral * price) / icr;
        } else {
            // Trove is inactive - I will use initial ICR to compute debt
            // 200e18 - 200 LUSD gas compensation to liquidators
            amtToBorrow = (_collateral * price) / INITIAL_ICR - 200e18;
        }

        if (!TROVE_MANAGER.checkRecoveryMode(price)) {
            // Liquity is not in recovery mode so borrowing fee applies
            uint256 borrowingRate = TROVE_MANAGER.getBorrowingRateWithDecay();
            amtToBorrow = (amtToBorrow * 1e18) / (borrowingRate + 1e18);
        }
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view override(ERC20) returns (uint256) {
        return super.totalSupply() - DUST;
    }

    /**
     * @notice Borrow LUSD
     * @param _collateral Amount of ETH denominated in Wei
     * @param _maxFee Maximum borrowing fee
     * @return tbMinted Amount of TB minted for borrower.
     * @return lusdBorrowed Amount of LUSD borrowed.
     */
    function _borrow(uint256 _collateral, uint64 _maxFee) private returns (uint256 tbMinted, uint256 lusdBorrowed) {
        lusdBorrowed = computeAmtToBorrow(_collateral); // LUSD amount to borrow
        (uint256 debtBefore,,,) = TROVE_MANAGER.getEntireDebtAndColl(address(this));

        (address upperHint, address lowerHint) = _getHints();
        BORROWER_OPERATIONS.adjustTrove{value: _collateral}(_maxFee, 0, lusdBorrowed, true, upperHint, lowerHint);
        (uint256 debtAfter,,,) = TROVE_MANAGER.getEntireDebtAndColl(address(this));
        // tbMinted = amount of TB to mint = (debtIncrease [LUSD] / debtBefore [LUSD]) * tbTotalSupply
        // debtIncrease = debtAfter - debtBefore
        // In case no redistribution took place (TB/LUSD = 1) then debt_before = TB_total_supply
        // and debt_increase amount of TB is minted.
        // In case there was redistribution, 1 TB corresponds to more than 1 LUSD and the amount of TB minted
        // will be lower than the amount of LUSD borrowed.
        tbMinted = ((debtAfter - debtBefore) * totalSupply()) / debtBefore;
        _mint(address(this), tbMinted);
    }

    /**
     * @notice Repay debt.
     * @param _tbAmount Amount of TB to burn.
     * @param _interactionNonce Same as in convert(...) method.
     * @return collateral Amount of collateral withdrawn.
     * @return lusdReturned Amount of LUSD returned (non-zero only if the trove was partially redeemed)
     */
    function _repay(uint256 _tbAmount, uint256 _interactionNonce)
        private
        returns (uint256 collateral, uint256 lusdReturned)
    {
        (uint256 debtBefore, uint256 collBefore,,) = TROVE_MANAGER.getEntireDebtAndColl(address(this));
        // Compute how much debt to be repay
        uint256 tbTotalSupply = totalSupply(); // SLOAD optimization
        uint256 debtToRepay = (_tbAmount * debtBefore) / tbTotalSupply;
        if (debtToRepay > _tbAmount) revert ErrorLib.InvalidOutputB();

        // Compute how much collateral to withdraw
        uint256 collToWithdraw = (_tbAmount * collBefore) / tbTotalSupply;

        // Repay _totalInputValue of LUSD and withdraw collateral
        (address upperHint, address lowerHint) = _getHints();
        BORROWER_OPERATIONS.adjustTrove(0, collToWithdraw, debtToRepay, false, upperHint, lowerHint);
        lusdReturned = _tbAmount - debtToRepay; // LUSD to return --> 0 unless trove was partially redeemed
        // Burn input TB and return ETH to rollup processor
        collateral = address(this).balance;
        _burn(address(this), _tbAmount);
        IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: collateral}(_interactionNonce);
    }

    /**
     * @notice Repay debt by selling part of the collateral for LUSD.
     * @param _totalInputValue Amount of TB to burn (and input LUSD to use for repayment if `_lusdInput` param is set
     *                         to true).
     * @param _maxPrice Maximum acceptable price of LUSD denominated in ETH.
     * @param _interactionNonce Same as in convert(...) method.
     * @param _lusdInput If true the debt will be covered by both the LUSD on input and by selling part of the
     *                   collateral. If false the debt will be covered only by selling the collateral.
     * @return collateralReturned Amount of collateral withdrawn.
     * @return tbReturned Amount of TB returned (non-zero only when the flash swap fails)
     * @dev It's important that CR never drops because if the trove was near minimum CR (MCR) the tx would revert.
     *      This would effectively stop users from being able to exit. Unfortunately users are also not able
     *      to exit when Liquity is in recovery mode (total collateral ratio < 150%) because in such a case
     *      only pure collateral top-up or debt repayment is allowed.
     *      To avoid CR from ever dropping bellow MCR I came up with the following construction:
     *        1) Flash swap USDC to LUSD,
     *        2) repay the user's trove debt in full (in the 1st callback),
     *        3) flash swap WETH to USDC with recipient being the LUSD_USDC_POOL - this pays for the first swap,
     *        4) in the 2nd callback deposit part of the withdrawn collateral to WETH and pay for the 2nd swap.
     *      In case the flash swap fails only a part of the debt gets repaid and the remaining TB balance corresponding
     *      to the unpaid debt gets returned.
     *      Note: Since owner is not able to exit until all the TB of everyone else gets burned his funds will be
     *      stuck forever unless the Uniswap pools recover.
     */
    function _repayWithCollateral(
        uint256 _totalInputValue,
        uint256 _maxPrice,
        uint256 _interactionNonce,
        bool _lusdInput
    ) private returns (uint256 collateralReturned, uint256 tbReturned) {
        (uint256 debtBefore, uint256 collBefore,,) = TROVE_MANAGER.getEntireDebtAndColl(address(this));
        // Compute how much debt to be repay
        uint256 tbTotalSupply = totalSupply(); // SLOAD optimization
        uint256 debtToRepay = (_totalInputValue * debtBefore) / tbTotalSupply;
        uint256 collToWithdraw = (_totalInputValue * collBefore) / tbTotalSupply;

        uint256 lusdToBuy;
        if (_lusdInput) {
            // Reverting here because an incorrect flow has been chosen --> there is no reason to be using flash swaps
            // when the amount of LUSD on input is enough to cover the debt
            if (debtToRepay <= _totalInputValue) revert ErrorLib.InvalidOutputB();
            lusdToBuy = debtToRepay - _totalInputValue;
        } else {
            lusdToBuy = debtToRepay;
        }

        // Saving a balance to a local variable to later get a `collateralReturned` value unaffected by a previously
        // held balance --> This is important because if we would set `collateralReturned` to `address(this).balance`
        // the value might be larger than `collToWithdraw` which could cause underflow when computing
        // `collateralSoldToUniswap`
        uint256 ethBalanceBeforeSwap = address(this).balance;

        (bool success,) = LUSD_USDC_POOL.call(
            abi.encodeWithSignature(
                "swap(address,bool,int256,uint160,bytes)",
                address(this), // recipient
                false, // zeroForOne
                -int256(lusdToBuy),
                SQRT_PRICE_LIMIT_X96,
                abi.encode(SwapCallbackData({debtToRepay: debtToRepay, collToWithdraw: collToWithdraw}))
            )
        );

        if (success) {
            // Note: Debt repayment took place in the `uniswapV3SwapCallback(...)` function
            collateralReturned = address(this).balance - ethBalanceBeforeSwap;

            {
                // Check that at most `maxCostInETH` of ETH collateral was sold for `debtToRepay` worth of LUSD
                uint256 maxCostInETH = (lusdToBuy * _maxPrice) / PRECISION;
                uint256 collateralSoldToUniswap = collToWithdraw - collateralReturned;
                if (collateralSoldToUniswap > maxCostInETH) revert MaxCostExceeded();
            }

            // Burn all input TB
            _burn(address(this), _totalInputValue);
        } else if (_lusdInput) {
            // Flash swap failed and some LUSD was provided on input --> repay as much debt as you can with current
            // LUSD balance and return the remaining TB
            debtToRepay = _totalInputValue;
            uint256 tbToBurn = (debtToRepay * tbTotalSupply) / debtBefore;
            collToWithdraw = (tbToBurn * collBefore) / tbTotalSupply;

            {
                // Repay _totalInputValue of LUSD and withdraw collateral
                (address upperHint, address lowerHint) = _getHints();
                BORROWER_OPERATIONS.adjustTrove(0, collToWithdraw, debtToRepay, false, upperHint, lowerHint);
            }

            tbReturned = _totalInputValue - tbToBurn;
            _burn(address(this), tbToBurn);
            collateralReturned = address(this).balance;
        } else {
            revert SwapFailed();
        }

        // Return ETH to rollup processor
        IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: collateralReturned}(_interactionNonce);
    }

    /**
     * @notice Redeem collateral.
     * @param _tbAmount Amount of TB to burn.
     * @param _interactionNonce Same as in convert(...) method.
     * @return collateral Amount of collateral withdrawn.
     */
    function _redeem(uint256 _tbAmount, uint256 _interactionNonce) private returns (uint256 collateral) {
        if (!collateralClaimed) {
            BORROWER_OPERATIONS.claimCollateral();
            collateralClaimed = true;
        }
        collateral = (address(this).balance * _tbAmount) / totalSupply();
        _burn(address(this), _tbAmount);
        IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: collateral}(_interactionNonce);
    }

    /**
     * @notice Get lower and upper insertion hints.
     * @return upperHint Upper insertion hint.
     * @return lowerHint Lower insertion hint.
     * @dev See https://github.com/liquity/dev#supplying-hints-to-trove-operations for more details on hints.
     */
    function _getHints() private view returns (address upperHint, address lowerHint) {
        return (SORTED_TROVES.getPrev(address(this)), SORTED_TROVES.getNext(address(this)));
    }
}
