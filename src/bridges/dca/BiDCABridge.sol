// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";

import {IWETH} from "../../interfaces/IWETH.sol";

import {SafeCastLib} from "./SafeCastLib.sol";

/**
 * @notice Initial abstract implementation of "Dollar" Cost Averaging.
 * The bridge implements a bidirectional dollar cost averaging protocol,
 * allowing users to go either direction between two tokens A and B.
 * The "order" is executed over a period of time, instead of all at once.
 * For Eth and Dai, this allows the user to sell Dai to buy Eth over X days, and vice versa.
 * The timeperiod is divided into ticks, with each tick keeping track of the funds that should be traded in that tick.
 * As well as the price, and how much have been received in return.
 * To "balance" the scheme, an external party can buy assets at the orace-price (no slippage).
 * The amount that can be bought by the external party, depends on the ticks and how much can be matched internally.
 * As part of the balancing act, each tick will match the A and B holdings it has to sell, using the oracle price
 * (or infer price from prior price and current price).
 * The excess from this internal matching is then sold off to the caller at oracle price, to match his offer.
 * The rebalancing is expected to be done by arbitrageurs when prices deviate sufficiently between the oracle and dexes.
 * The finalise function is incentivised by giving part of the traded value to the `tx.origin` (msg.sender always rollup processor).
 * Extensions to this bridge can be made such that the external party can be Uniswap or another dex.
 * An extension should also define the oracle to be used for the price.
 * @dev Built for assets with 18 decimals precision
 * @dev A contract that inherits must handle the case for forcing a swap through a DEX.
 * @author Lasse Herskind (LHerskind on GitHub).
 */
abstract contract BiDCABridge is BridgeBase {
    using SafeERC20 for IERC20;
    using SafeCastLib for uint256;
    using SafeCastLib for uint128;

    error FeeTooLarge();
    error PositionAlreadyExists();
    error NoDeposits();

    /**
     * @notice A struct used in-memory to get around stack-to-deep errors
     * @member currentPrice Current oracle price
     * @member earliestTickWithAvailableA Earliest tick with available asset A
     * @member earliestTickWithAvailableB Earliest tick with available asset B
     * @member offerAInB Amount of asset B that is offered to be bought at the current price for A
     * @member offerBInA Amount of asset A that is offered to be bought at the current price for B
     * @member protocolSoldA Amount of asset A the bridge sold
     * @member protocolSoldB Amount of asset B the bridge sold
     * @member protocolBoughtA Amount of asset A the bridge bought
     * @member protocolBoughtB Amount of asset B the bridge bought
     * @member lastUsedPrice Last used price during rebalancing (cache in case new price won't be available)
     * @member lastUsedPriceTime Time at which last used price was set
     * @member availableA The amount of asset A that is available
     * @member availableB The amount of asset B that is available
     */
    struct RebalanceValues {
        uint256 currentPrice;
        uint256 earliestTickWithAvailableA;
        uint256 earliestTickWithAvailableB;
        uint256 offerAInB;
        uint256 offerBInA;
        uint256 protocolSoldA;
        uint256 protocolSoldB;
        uint256 protocolBoughtA;
        uint256 protocolBoughtB;
        uint256 lastUsedPrice;
        uint256 lastUsedPriceTime;
        uint256 availableA;
        uint256 availableB;
    }

    /**
     * @notice A struct representing 1 DCA position
     * @member amount Amount of asset A or B to be sold
     * @member start Index of the first tick this position touches
     * @member end Index of the last tick this position touches
     * @member aToB True if A is being sold to B, false otherwise
     */
    struct DCA {
        uint128 amount;
        uint32 start;
        uint32 end;
        bool aToB;
    }

    /**
     * @notice A struct defining one direction in a tick
     * @member sold Amount of asset sold
     * @member bought Amount of asset bought
     */
    struct SubTick {
        uint128 sold;
        uint128 bought;
    }

    /**
     * @notice A container for Tick related data
     * @member availableA Amount of A available in a tick for sale
     * @member availableB Amount of B available in a tick for sale
     * @member poke A value used only to initialize a storage slot
     * @member aToBSubTick A struct capturing info of A to B trades
     * @member aToBSubTick A struct capturing info of B to A trades
     * @member priceAToB A price of A denominated in B
     * @member priceTime A time at which price was last updated
     */
    struct Tick {
        uint120 availableA;
        uint120 availableB;
        uint16 poke;
        SubTick aToBSubTick;
        SubTick bToASubTick;
        uint128 priceOfAInB;
        uint32 priceTime;
    }

    IWETH internal constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    uint256 public constant FEE_DIVISOR = 10000;

    // The assets that are DCAed between
    IERC20 public immutable ASSET_A;
    IERC20 public immutable ASSET_B;

    // The timespan that a tick covers
    uint256 public immutable TICK_SIZE;
    uint256 public immutable FEE;

    // The earliest tick where we had available A or B respectively.
    uint32 public earliestTickWithAvailableA;
    uint32 public earliestTickWithAvailableB;

    // tick id => Tick.
    mapping(uint256 => Tick) public ticks;
    // nonce => DCA
    mapping(uint256 => DCA) public dcas;

    /**
     * @notice Constructor
     * @param _rollupProcessor The address of the rollup processor for the bridge
     * @param _assetA The address of asset A
     * @param _assetB The address of asset B
     * @param _tickSize The time-span that each tick covers in seconds
     * @dev Smaller _tickSizes will increase looping and gas costs
     */
    constructor(
        address _rollupProcessor,
        address _assetA,
        address _assetB,
        uint256 _tickSize,
        uint256 _fee
    ) BridgeBase(_rollupProcessor) {
        ASSET_A = IERC20(_assetA);
        ASSET_B = IERC20(_assetB);
        TICK_SIZE = _tickSize;

        IERC20(_assetA).safeApprove(_rollupProcessor, type(uint256).max);
        IERC20(_assetB).safeApprove(_rollupProcessor, type(uint256).max);

        if (_fee > FEE_DIVISOR) {
            revert FeeTooLarge();
        }
        FEE = _fee;
    }

    receive() external payable {}

    /**
     * @notice Helper used to poke storage from next tick and `_ticks` forwards
     * @param _numTicks The number of ticks to poke
     */
    function pokeNextTicks(uint256 _numTicks) external {
        pokeTicks(_nextTick(block.timestamp), _numTicks);
    }

    /**
     * @notice Helper used to poke storage of ticks to make deposits more consistent in gas usage
     * @dev First sstore is very expensive, so by doing it as this, we can prepare it before deposit
     * @param _startTick The first tick to poke
     * @param _numTicks The number of ticks to poke
     */
    function pokeTicks(uint256 _startTick, uint256 _numTicks) public {
        for (uint256 i = _startTick; i < _startTick + _numTicks; i++) {
            ticks[i].poke++;
        }
    }

    /**
     * @notice Rebalances ticks using internal values first, then with externally provided assets.
     * Ticks are balanced internally using the price at the specific tick (either stored in tick, or interpolated).
     * Leftover assets are sold using current price to fill as much of the offer as possible.
     * @param _offerA The amount of asset A that is offered for sale to the bridge
     * @param _offerB The amount of asset B that is offered for sale to the bridge
     * @return flowA The flow of asset A from the bridge POV, e.g., >0 = buying of tokens, <0 = selling tokens
     * @return flowB The flow of asset B from the bridge POV, e.g., >0 = buying of tokens, <0 = selling tokens
     */
    function rebalanceAndFill(uint256 _offerA, uint256 _offerB) public returns (int256, int256) {
        return rebalanceAndFill(_offerA, _offerB, type(uint256).max);
    }

    /**
     * @notice Rebalances ticks using internal values first, then with externally provided assets.
     * Ticks are balanced internally using the price at the specific tick (either stored in tick, or interpolated).
     * Leftover assets are sold using current price to fill as much of the offer as possible.
     * @param _offerA The amount of asset A that is offered for sale to the bridge
     * @param _offerB The amount of asset B that is offered for sale to the bridge
     * @param _upperTick The upper limit for ticks (useful gas-capped rebalancing)
     * @return flowA The flow of asset A from the bridge POV, e.g., >0 = buying of tokens, <0 = selling tokens
     * @return flowB The flow of asset B from the bridge POV, e.g., >0 = buying of tokens, <0 = selling tokens
     */
    function rebalanceAndFill(
        uint256 _offerA,
        uint256 _offerB,
        uint256 _upperTick
    ) public returns (int256, int256) {
        (int256 flowA, int256 flowB, , ) = _rebalanceAndFill(_offerA, _offerB, getPrice(), _upperTick, false);
        if (flowA > 0) {
            ASSET_A.safeTransferFrom(msg.sender, address(this), uint256(flowA));
        } else if (flowA < 0) {
            ASSET_A.safeTransfer(msg.sender, uint256(-flowA));
        }

        if (flowB > 0) {
            ASSET_B.safeTransferFrom(msg.sender, address(this), uint256(flowB));
        } else if (flowB < 0) {
            ASSET_B.safeTransfer(msg.sender, uint256(-flowB));
        }

        return (flowA, flowB);
    }

    /**
     * @notice Function to create DCA position from `_inputAssetA` to `_outputAssetA` over `_ticks` ticks.
     * @param _inputAssetA The asset to be sold
     * @param _outputAssetA The asset to be bought
     * @param _inputValue The value of `_inputAssetA` to be sold
     * @param _interactionNonce The unique identifier for the interaction, used to identify the DCA position
     * @param _numTicks The auxdata, passing the number of ticks the position should run
     * @return Will always return 0 assets, and isAsync = true.
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64 _numTicks,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256,
            uint256,
            bool
        )
    {
        address inputAssetAddress = _inputAssetA.erc20Address;
        address outputAssetAddress = _outputAssetA.erc20Address;

        if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
            WETH.deposit{value: _inputValue}();
            inputAssetAddress = address(WETH);
        }
        if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
            outputAssetAddress = address(WETH);
        }

        if (inputAssetAddress != address(ASSET_A) && inputAssetAddress != address(ASSET_B)) {
            revert ErrorLib.InvalidInputA();
        }
        bool aToB = inputAssetAddress == address(ASSET_A);

        if (outputAssetAddress != (aToB ? address(ASSET_B) : address(ASSET_A))) {
            revert ErrorLib.InvalidOutputA();
        }
        if (dcas[_interactionNonce].start != 0) {
            revert PositionAlreadyExists();
        }

        _deposit(_interactionNonce, _inputValue, _numTicks, aToB);
        return (0, 0, true);
    }

    /**
     * @notice Function used to close a completed DCA position
     * @param _outputAssetA The asset bought with the DCA position
     * @param _interactionNonce The identifier for the DCA position
     * @return outputValueA The amount of assets bought
     * @return interactionComplete True if the interaction is completed and can be executed, false otherwise
     */
    function finalise(
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _interactionNonce,
        uint64
    )
        external
        payable
        virtual
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256,
            bool interactionComplete
        )
    {
        uint256 accumulated;
        (accumulated, interactionComplete) = getAccumulated(_interactionNonce);

        if (interactionComplete) {
            bool toEth;

            address outputAssetAddress = _outputAssetA.erc20Address;
            if (_outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                toEth = true;
                outputAssetAddress = address(WETH);
            }

            if (outputAssetAddress != (dcas[_interactionNonce].aToB ? address(ASSET_B) : address(ASSET_A))) {
                revert ErrorLib.InvalidOutputA();
            }

            uint256 incentive;
            if (FEE > 0) {
                incentive = (accumulated * FEE) / FEE_DIVISOR;
            }

            outputValueA = accumulated - incentive;
            delete dcas[_interactionNonce];

            if (toEth) {
                WETH.withdraw(outputValueA);
                IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(_interactionNonce);
            }

            if (incentive > 0) {
                // Cannot use the `msg.sender` as that would simply be the rollup.
                IERC20(outputAssetAddress).safeTransfer(tx.origin, incentive);
            }
        }
    }

    /**
     * @notice The brice of A in B, e.g., 10 would mean 1 A = 10 B
     * @return priceAToB measured with precision 1e18
     */
    function getPrice() public virtual returns (uint256);

    /**
     * @notice Computes the value of `_amount` A tokens in B tokens
     * @param _amount The amount of A tokens
     * @param _priceAToB The price of A tokens in B
     * @param _roundUp Flag to round up, if true rounding up, otherwise rounding down
     */
    function denominateAssetAInB(
        uint256 _amount,
        uint256 _priceAToB,
        bool _roundUp
    ) public pure returns (uint256) {
        if (_roundUp) {
            return (_amount * _priceAToB + 1e18 - 1) / 1e18;
        }
        return (_amount * _priceAToB) / 1e18;
    }

    /**
     * @notice Computes the value of `_amount` A tokens in B tokens
     * @param _amount The amount of A tokens
     * @param _priceAToB The price of A tokens in B
     * @param _roundUp Flag to round up, if true rounding up, otherwise rounding down
     */
    function denominateAssetBInA(
        uint256 _amount,
        uint256 _priceAToB,
        bool _roundUp
    ) public pure returns (uint256) {
        if (_roundUp) {
            return (_amount * 1e18 + _priceAToB - 1) / _priceAToB;
        }
        return (_amount * 1e18) / _priceAToB;
    }

    /**
     * @notice Helper to fetch the tick at `_tick`
     * @param _tick The tick to fetch
     * @return The Tick structure
     */
    function getTick(uint256 _tick) public view returns (Tick memory) {
        return ticks[_tick];
    }

    /**
     * @notice Helper to fetch the DCA at `_nonce`
     * @param _nonce The DCA to fetch
     * @return The DCA structure
     */
    function getDCA(uint256 _nonce) public view returns (DCA memory) {
        return dcas[_nonce];
    }

    /**
     * @notice Helper to compute the amount of available tokens (not taking rebalancing into account)
     * @return availableA Available amount of token A
     * @return availableB Available amount of token B
     */
    function getAvailable() public view returns (uint256 availableA, uint256 availableB) {
        uint256 start = _earliestUsedTick(earliestTickWithAvailableA, earliestTickWithAvailableB);
        uint256 lastTick = block.timestamp / TICK_SIZE;
        for (uint256 i = start; i <= lastTick; i++) {
            availableA += ticks[i].availableA;
            availableB += ticks[i].availableB;
        }
    }

    /**
     * @notice Helper to get the amount of accumulated tokens for a specific DCA (and a flag for finalisation readiness)
     * @param _nonce The DCA to fetch
     * @return accumulated The amount of assets accumulated
     * @return ready A flag that is true if the accumulation has completed, false otherwise
     */
    function getAccumulated(uint256 _nonce) public view returns (uint256 accumulated, bool ready) {
        DCA memory dca = dcas[_nonce];
        uint256 start = dca.start;
        uint256 end = dca.end;
        uint256 tickAmount = dca.amount / (end - start);
        bool aToB = dca.aToB;

        ready = true;

        for (uint256 i = start; i < end; i++) {
            Tick storage tick = ticks[i];
            (uint256 available, uint256 sold, uint256 bought) = aToB
                ? (tick.availableA, tick.aToBSubTick.sold, tick.aToBSubTick.bought)
                : (tick.availableB, tick.bToASubTick.sold, tick.bToASubTick.bought);
            ready = ready && available == 0 && sold > 0;
            accumulated += sold == 0 ? 0 : (bought * tickAmount) / (sold + available);
        }
    }

    /**
     * @notice Computes the next tick
     * @dev    Note that the return value can be the current tick if we are exactly at the threshold
     * @return The next tick
     */
    function _nextTick(uint256 _time) internal view returns (uint256) {
        return ((_time + TICK_SIZE - 1) / TICK_SIZE);
    }

    function _min(uint256 _a, uint256 _b) internal pure returns (uint256) {
        return _a > _b ? _b : _a;
    }

    /**
     * @notice Create a new DCA position starting at next tick and accumulates the available assets to the future ticks.
     * @param _nonce The interaction nonce
     * @param _amount The amount of assets deposited
     * @param _ticks The number of ticks that the position span
     * @param _aToB A flag that is true if input asset is assetA and false otherwise.
     */
    function _deposit(
        uint256 _nonce,
        uint256 _amount,
        uint256 _ticks,
        bool _aToB
    ) internal {
        uint256 nextTick = _nextTick(block.timestamp);
        if (_aToB && earliestTickWithAvailableA == 0) {
            earliestTickWithAvailableA = nextTick.toU32();
        }
        if (!_aToB && earliestTickWithAvailableB == 0) {
            earliestTickWithAvailableB = nextTick.toU32();
        }
        // Update prices of last tick, might be 1 second in the past.
        ticks[nextTick - 1].priceOfAInB = getPrice().toU128();
        ticks[nextTick - 1].priceTime = block.timestamp.toU32();

        uint256 tickAmount = _amount / _ticks;
        for (uint256 i = nextTick; i < nextTick + _ticks; i++) {
            if (_aToB) {
                ticks[i].availableA += tickAmount.toU120();
            } else {
                ticks[i].availableB += tickAmount.toU120();
            }
        }
        dcas[_nonce] = DCA({
            amount: _amount.toU128(),
            start: nextTick.toU32(),
            end: (nextTick + _ticks).toU32(),
            aToB: _aToB
        });
    }

    /**
     * @notice Rebalances ticks using internal values first, then with externally provided assets.
     * Ticks are balanced internally using the price at the specific tick (either stored in tick, or interpolated).
     * Leftover assets are sold using current price to fill as much of the offer as possible.
     * @param _offerA The amount of asset A that is offered for sale to the bridge
     * @param _offerB The amount of asset B that is offered for sale to the bridge
     * @param _currentPrice Current oracle price
     * @param _self A flag that is true if rebalancing with self, e.g., swapping available funds with dex and rebalancing, and false otherwise
     * @param _upperTick A upper limit for the ticks, useful for gas-capped execution
     * @return flowA The flow of asset A from the bridge POV, e.g., >0 = buying of tokens, <0 = selling tokens
     * @return flowB The flow of asset B from the bridge POV, e.g., >0 = buying of tokens, <0 = selling tokens
     * @return availableA The amount of asset A that is available after the rebalancing
     * @return availableB The amount of asset B that is available after the rebalancing
     */
    function _rebalanceAndFill(
        uint256 _offerA,
        uint256 _offerB,
        uint256 _currentPrice,
        uint256 _upperTick,
        bool _self
    )
        internal
        returns (
            int256,
            int256,
            uint256,
            uint256
        )
    {
        RebalanceValues memory vars;
        vars.currentPrice = _currentPrice;

        // Cache and use earliest ticks with available funds
        vars.earliestTickWithAvailableA = earliestTickWithAvailableA;
        vars.earliestTickWithAvailableB = earliestTickWithAvailableB;
        uint256 earliestTick = _earliestUsedTick(vars.earliestTickWithAvailableA, vars.earliestTickWithAvailableB);

        // Cache last used price for use in case we don't have a fresh price.
        vars.lastUsedPrice = ticks[earliestTick].priceOfAInB;
        vars.lastUsedPriceTime = ticks[earliestTick].priceTime;
        if (vars.lastUsedPrice == 0) {
            uint256 lookBack = earliestTick;
            while (vars.lastUsedPrice == 0) {
                lookBack--;
                vars.lastUsedPrice = ticks[lookBack].priceOfAInB;
                vars.lastUsedPriceTime = ticks[lookBack].priceTime;
            }
        }

        // Compute the amount of B that is offered to be bought at current price for A. Round down
        vars.offerAInB = denominateAssetAInB(_offerA, vars.currentPrice, false);
        // Compute the amount of A that is offered to be bought at current price for B. Round down
        vars.offerBInA = denominateAssetBInA(_offerB, vars.currentPrice, false);

        uint256 nextTick = _nextTick(block.timestamp);
        // Update the latest tick, might be 1 second in the past.
        ticks[nextTick - 1].priceOfAInB = vars.currentPrice.toU128();
        ticks[nextTick - 1].priceTime = block.timestamp.toU32();

        for (uint256 i = earliestTick; i < _min(nextTick, _upperTick); i++) {
            // Load a cache
            Tick memory tick = ticks[i];

            _rebalanceTickInternally(vars, tick, i);
            _useAOffer(vars, tick, _self);
            _useBOffer(vars, tick, _self);

            // If no more available and earliest is current tick, increment tick.
            if (tick.availableA == 0 && vars.earliestTickWithAvailableA == i) {
                vars.earliestTickWithAvailableA += 1;
            }
            if (tick.availableB == 0 && vars.earliestTickWithAvailableB == i) {
                vars.earliestTickWithAvailableB += 1;
            }

            // Add the leftover A and B from the tick to total available
            vars.availableA += tick.availableA;
            vars.availableB += tick.availableB;

            // Update the storage
            ticks[i] = tick;
        }

        if (vars.earliestTickWithAvailableA > earliestTickWithAvailableA) {
            earliestTickWithAvailableA = vars.earliestTickWithAvailableA.toU32();
        }
        if (vars.earliestTickWithAvailableB > earliestTickWithAvailableB) {
            earliestTickWithAvailableB = vars.earliestTickWithAvailableB.toU32();
        }

        // Compute flow of tokens, from the POV of this contract, e.g., >0 is inflow, <0 outflow
        int256 flowA = int256(vars.protocolBoughtA) - int256(vars.protocolSoldA);
        int256 flowB = int256(vars.protocolBoughtB) - int256(vars.protocolSoldB);

        return (flowA, flowB, vars.availableA, vars.availableB);
    }

    /**
     * @notice Perform internal rebalancing of a single tick using available balances
     * @dev Heavily uses that internal functions are passing reference to memory structures
     *
     */
    function _rebalanceTickInternally(
        RebalanceValues memory _vars,
        Tick memory _tick,
        uint256 _tickId
    ) internal view {
        // Only perform internal rebalance if we have both assets available, otherwise nothing to rebalance
        if (_tick.availableA > 0 && _tick.availableB > 0) {
            uint256 price = _tick.priceOfAInB;

            // If a price is stored at tick, update the last used price and timestamp. Otherwise interpolate.
            if (price > 0) {
                _vars.lastUsedPrice = price;
                _vars.lastUsedPriceTime = _tick.priceTime;
            } else {
                int256 slope = (int256(_vars.currentPrice) - int256(_vars.lastUsedPrice)) /
                    int256(block.timestamp - _vars.lastUsedPriceTime);
                // lastUsedPriceTime will always be an earlier tick than this.
                uint256 dt = _tickId * TICK_SIZE + TICK_SIZE / 2 - _vars.lastUsedPriceTime;
                int256 _price = int256(_vars.lastUsedPrice) + slope * int256(dt);
                if (_price <= 0) {
                    price = 0;
                } else {
                    price = uint256(_price);
                }
            }

            // To compare we need same basis. Compute value of the available A in base B. Round down
            uint128 availableADenominatedInB = denominateAssetAInB(_tick.availableA, price, false).toU128();

            // If more value in A than B, we can use all available B. Otherwise, use all available A
            if (availableADenominatedInB > _tick.availableB) {
                // The value of all available B in asset A. Round down
                uint128 availableBDenominatedInA = denominateAssetBInA(_tick.availableB, price, false).toU128();

                // Update Asset A
                _tick.aToBSubTick.bought += _tick.availableB;
                _tick.aToBSubTick.sold += availableBDenominatedInA;

                // Update Asset B
                _tick.bToASubTick.bought += availableBDenominatedInA;
                _tick.bToASubTick.sold += _tick.availableB;

                // Update available values
                _tick.availableA -= availableBDenominatedInA.toU120();
                _tick.availableB = 0;
            } else {
                // We got more B than A, fill everything in A and part of B

                // Update Asset B
                _tick.bToASubTick.bought += _tick.availableA;
                _tick.bToASubTick.sold += availableADenominatedInB;

                // Update Asset A
                _tick.aToBSubTick.bought += availableADenominatedInB;
                _tick.aToBSubTick.sold += _tick.availableA;

                // Update available values
                _tick.availableA = 0;
                _tick.availableB -= availableADenominatedInB.toU120();
            }
        }
    }

    /**
     * @notice Fills as much of the A offered as possible
     * @dev Heavily uses that internal functions are passing reference to memory structures
     * @param _self True if buying from "self" false otherwise.
     */
    function _useAOffer(
        RebalanceValues memory _vars,
        Tick memory _tick,
        bool _self
    ) internal pure {
        if (_vars.offerAInB > 0 && _tick.availableB > 0) {
            uint128 amountBSold = _vars.offerAInB.toU128();
            // We cannot buy more than available
            if (_vars.offerAInB > _tick.availableB) {
                amountBSold = _tick.availableB;
            }
            // Underpays actual price if self, otherwise overpay (to not mess rounding)
            uint128 assetAPayment = denominateAssetBInA(amountBSold, _vars.currentPrice, !_self).toU128();

            _tick.availableB -= amountBSold.toU120();
            _tick.bToASubTick.sold += amountBSold;
            _tick.bToASubTick.bought += assetAPayment;

            _vars.offerAInB -= amountBSold;
            _vars.protocolSoldB += amountBSold;
            _vars.protocolBoughtA += assetAPayment;
        }
    }

    /**
     * @notice Fills as much of the A offered as possible
     * @dev Heavily uses that internal functions are passing reference to memory structures
     * @param _self True if buying from "self" false otherwise.
     */
    function _useBOffer(
        RebalanceValues memory _vars,
        Tick memory _tick,
        bool _self
    ) internal pure {
        if (_vars.offerBInA > 0 && _tick.availableA > 0) {
            // Buying Asset A using Asset B
            uint128 amountASold = _vars.offerBInA.toU128();
            if (_vars.offerBInA > _tick.availableA) {
                amountASold = _tick.availableA;
            }
            // Underpays actual price if self, otherwise overpay (to not mess rounding)
            uint128 assetBPayment = denominateAssetAInB(amountASold, _vars.currentPrice, !_self).toU128();

            _tick.availableA -= amountASold.toU120();
            _tick.aToBSubTick.sold += amountASold;
            _tick.aToBSubTick.bought += assetBPayment;

            _vars.offerBInA -= amountASold;
            _vars.protocolSoldA += amountASold;
            _vars.protocolBoughtB += assetBPayment;
        }
    }

    /**
     * @notice Computes the earliest tick where we had available funds
     * @param _earliestTickA The ealiest tick with available A
     * @param _earliestTickB The ealiest tick with available B
     * @return The earliest tick with available assets
     */
    function _earliestUsedTick(uint256 _earliestTickA, uint256 _earliestTickB) internal pure returns (uint256) {
        uint256 start;
        if (_earliestTickA == 0 && _earliestTickB == 0) {
            revert NoDeposits();
        } else if (_earliestTickA * _earliestTickB == 0) {
            // one are zero (the both case is handled explicitly above)
            start = _earliestTickA > _earliestTickB ? _earliestTickA : _earliestTickB;
        } else {
            start = _earliestTickA < _earliestTickB ? _earliestTickA : _earliestTickB;
        }
        return start;
    }
}
