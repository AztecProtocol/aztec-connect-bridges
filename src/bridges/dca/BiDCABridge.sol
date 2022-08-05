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
 * Supports bidirectional "selling", e.g., A -> B and B -> A in same bridge
 * Will match internal orders first, before allowing external parties to trade.
 * @dev Built for assets with 18 decimals precision
 * @dev A contract that inherits must handle the case for forcing a swap through a DEX.
 * @author Lasse Herskind (LHerskind on GitHub).
 */
abstract contract BiDCABridge is BridgeBase {
    using SafeERC20 for IERC20;
    using SafeCastLib for uint256;
    using SafeCastLib for uint128;

    error PositionAlreadyExists();

    // Struct used in-memory to get around stack-to-deep
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
        uint256 lastUsedPriceTs;
        uint256 availableA;
        uint256 availableB;
    }

    // Struct packing a DCA position for storage
    struct DCA {
        uint128 total;
        uint32 start;
        uint32 end;
        bool assetA;
    }

    // Struct used for defining one direction in a tick
    struct SubTick {
        uint128 sold;
        uint128 bought;
    }

    // Struct describing a specific tick
    struct Tick {
        uint120 availableA;
        uint120 availableB;
        uint16 poke;
        SubTick assetAToB;
        SubTick assetBToA;
        uint128 priceAToB;
        uint32 priceUpdated;
    }

    IWETH internal constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    // The assets that are DCAed between
    IERC20 public immutable ASSET_A;
    IERC20 public immutable ASSET_B;

    // The timespan that a tick covers
    uint256 public immutable TICK_SIZE;

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
        uint256 _tickSize
    ) BridgeBase(_rollupProcessor) {
        ASSET_A = IERC20(_assetA);
        ASSET_B = IERC20(_assetB);
        TICK_SIZE = _tickSize;

        IERC20(_assetA).safeApprove(_rollupProcessor, type(uint256).max);
        IERC20(_assetB).safeApprove(_rollupProcessor, type(uint256).max);
    }

    receive() external payable {}

    /**
     * @notice Helper used to poke storage from next tick and `_ticks` forwards
     * @param _ticks The number of ticks to poke
     */
    function pokeNextTicks(uint256 _ticks) external {
        uint256 nextTick = ((block.timestamp + TICK_SIZE - 1) / TICK_SIZE);
        pokeTicks(nextTick, _ticks);
    }

    /**
     * @notice Helper used to poke storage of ticks to make deposits more consistent in gas usage
     * @dev First sstore is very expensive, so by doing it as this, we can prepare it before deposit
     * @param _startTick The first tick to poke
     * @param _ticks The number of ticks to poke
     */
    function pokeTicks(uint256 _startTick, uint256 _ticks) public {
        for (uint256 i = _startTick; i < _startTick + _ticks; i++) {
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
        (int256 flowA, int256 flowB, , ) = _rebalanceAndFill(_offerA, _offerB, getPrice(), false);
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
     * @param _ticks The auxdata, passing the number of ticks the position should run
     * @return Will always return 0 assets, and isAsync = true.
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64 _ticks,
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
        bool assetA = inputAssetAddress == address(ASSET_A);

        if (outputAssetAddress != (assetA ? address(ASSET_B) : address(ASSET_A))) {
            revert ErrorLib.InvalidOutputA();
        }
        if (dcas[_interactionNonce].start != 0) {
            revert PositionAlreadyExists();
        }

        _deposit(_interactionNonce, _inputValue, _ticks, assetA);
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

            if (outputAssetAddress != (dcas[_interactionNonce].assetA ? address(ASSET_B) : address(ASSET_A))) {
                revert ErrorLib.InvalidOutputA();
            }

            outputValueA = accumulated;
            delete dcas[_interactionNonce];

            if (toEth) {
                WETH.withdraw(accumulated);
                IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(_interactionNonce);
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
     * @return availableA The amount of token A that is available
     * @return availableB The amount of token B that is available
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
        uint256 tickAmount = dca.total / (end - start);
        bool assetA = dca.assetA;

        ready = true;

        for (uint256 i = start; i < end; i++) {
            Tick storage tick = ticks[i];
            (uint256 available, uint256 sold, uint256 bought) = assetA
                ? (tick.availableA, tick.assetAToB.sold, tick.assetAToB.bought)
                : (tick.availableB, tick.assetBToA.sold, tick.assetBToA.bought);
            ready = ready && available == 0 && sold > 0;
            accumulated += sold == 0 ? 0 : (bought * tickAmount) / (sold + available);
        }
    }

    /**
     * @notice Create a new DCA position starting at next tick and accumulates the available assets to the future ticks.
     * @param _nonce The interaction nonce
     * @param _amount The amount of assets deposited
     * @param _ticks The number of ticks that the position span
     * @param _assetA A flag that is true if input asset is assetA and false otherwise.
     */
    function _deposit(
        uint256 _nonce,
        uint256 _amount,
        uint256 _ticks,
        bool _assetA
    ) internal {
        uint256 nextTick = ((block.timestamp + TICK_SIZE - 1) / TICK_SIZE);
        if (_assetA && earliestTickWithAvailableA == 0) {
            earliestTickWithAvailableA = nextTick.toU32();
        }
        if (!_assetA && earliestTickWithAvailableB == 0) {
            earliestTickWithAvailableB = nextTick.toU32();
        }
        // Update prices of last tick, might be 1 second in the past.
        ticks[nextTick - 1].priceAToB = getPrice().toU128();
        ticks[nextTick - 1].priceUpdated = block.timestamp.toU32();

        uint256 tickAmount = _amount / _ticks;
        for (uint256 i = nextTick; i < nextTick + _ticks; i++) {
            if (_assetA) {
                ticks[i].availableA += tickAmount.toU120();
            } else {
                ticks[i].availableB += tickAmount.toU120();
            }
        }
        dcas[_nonce] = DCA({
            total: _amount.toU128(),
            start: nextTick.toU32(),
            end: (nextTick + _ticks).toU32(),
            assetA: _assetA
        });
    }

    /**
     * @notice Rebalances ticks using internal values first, then with externally provided assets.
     * Ticks are balanced internally using the price at the specific tick (either stored in tick, or interpolated).
     * Leftover assets are sold using current price to fill as much of the offer as possible.
     * @param _offerA The amount of asset A that is offered for sale to the bridge
     * @param _offerB The amount of asset B that is offered for sale to the bridge
     * @param _currentPrice The current price
     * @param _self A flag that is true if rebalancing with self, e.g., swapping available funds with dex and rebalancing, and false otherwise
     * @return flowA The flow of asset A from the bridge POV, e.g., >0 = buying of tokens, <0 = selling tokens
     * @return flowB The flow of asset B from the bridge POV, e.g., >0 = buying of tokens, <0 = selling tokens
     * @return availableA The amount of asset A that is available after the rebalancing
     * @return availableB The amount of asset B that is available after the rebalancing
     */
    function _rebalanceAndFill(
        uint256 _offerA,
        uint256 _offerB,
        uint256 _currentPrice,
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
        vars.lastUsedPrice = ticks[earliestTick].priceAToB;
        vars.lastUsedPriceTs = ticks[earliestTick].priceUpdated;
        if (vars.lastUsedPrice == 0) {
            uint256 lookBack = earliestTick;
            while (vars.lastUsedPrice == 0) {
                lookBack--;
                vars.lastUsedPrice = ticks[lookBack].priceAToB;
                vars.lastUsedPriceTs = ticks[lookBack].priceUpdated;
            }
        }

        // Compute the amount of B that can be bought at current prices for A given the offer. Round down
        vars.offerAInB = denominateAssetAInB(_offerA, vars.currentPrice, false);
        // Compute the amount of A that can be bought at current prices for B given the offer. Round down
        vars.offerBInA = denominateAssetBInA(_offerB, vars.currentPrice, false);

        uint256 nextTick = ((block.timestamp + TICK_SIZE - 1) / TICK_SIZE);
        // Update the latest tick, might be 1 second in the past.
        ticks[nextTick - 1].priceAToB = vars.currentPrice.toU128();
        ticks[nextTick - 1].priceUpdated = block.timestamp.toU32();

        for (uint256 i = earliestTick; i < nextTick; i++) {
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
        RebalanceValues memory vars,
        Tick memory tick,
        uint256 _tickId
    ) internal view {
        // Only perform internal rebalance if we have both assets available, otherwise nothing to rebalance
        if (tick.availableA > 0 && tick.availableB > 0) {
            uint256 price = tick.priceAToB;

            // If a price is stored at tick, update the last used price and timestamp. Otherwise interpolate.
            if (price > 0) {
                vars.lastUsedPrice = price;
                vars.lastUsedPriceTs = tick.priceUpdated;
            } else {
                int256 slope = (int256(vars.currentPrice) - int256(vars.lastUsedPrice)) /
                    int256(block.timestamp - vars.lastUsedPriceTs);
                // Could we ever enter a case where DT is in the past?
                // lastUsedPriceTs will always be an earlier tick than this.
                uint256 dt = _tickId * TICK_SIZE + TICK_SIZE / 2 - vars.lastUsedPriceTs;
                int256 _price = int256(vars.lastUsedPrice) + slope * int256(dt);
                if (_price <= 0) {
                    price = 0;
                } else {
                    price = uint256(_price);
                }
            }

            // To compare we need same basis. Compute value of the available A in base B. Round down
            uint128 availableADenominatedInB = denominateAssetAInB(tick.availableA, price, false).toU128();

            // If more value in A than B, we can use all available B. Otherwise, use all available A
            if (availableADenominatedInB > tick.availableB) {
                // The value of all available B in asset A. Round down
                uint128 availableBDenominatedInA = denominateAssetBInA(tick.availableB, price, false).toU128();

                // Update Asset A
                tick.assetAToB.bought += tick.availableB;
                tick.assetAToB.sold += availableBDenominatedInA;

                // Update Asset B
                tick.assetBToA.bought += availableBDenominatedInA;
                tick.assetBToA.sold += tick.availableB;

                // Update available values
                tick.availableA -= availableBDenominatedInA.toU120();
                tick.availableB = 0;
            } else {
                // We got more B than A, fill everything in A and part of B

                // Update Asset B
                tick.assetBToA.bought += tick.availableA;
                tick.assetBToA.sold += availableADenominatedInB;

                // Update Asset A
                tick.assetAToB.bought += availableADenominatedInB;
                tick.assetAToB.sold += tick.availableA;

                // Update available values
                tick.availableA = 0;
                tick.availableB -= availableADenominatedInB.toU120();
            }
        }
    }

    /**
     * @notice Fills as much of the A offered as possible
     * @dev Heavily uses that internal functions are passing reference to memory structures
     * @param _self True if buying from "self" false otherwise.
     */
    function _useAOffer(
        RebalanceValues memory vars,
        Tick memory tick,
        bool _self
    ) internal pure {
        if (vars.offerAInB > 0 && tick.availableB > 0) {
            uint128 amountBSold = vars.offerAInB.toU128();
            // We cannot buy more than available
            if (vars.offerAInB > tick.availableB) {
                amountBSold = tick.availableB;
            }
            // Underpays actual price if self, otherwise overpay (to not mess rounding)
            uint128 assetAPayment = denominateAssetBInA(amountBSold, vars.currentPrice, !_self).toU128();

            tick.availableB -= amountBSold.toU120();
            tick.assetBToA.sold += amountBSold;
            tick.assetBToA.bought += assetAPayment;

            vars.offerAInB -= amountBSold;
            vars.protocolSoldB += amountBSold;
            vars.protocolBoughtA += assetAPayment;
        }
    }

    /**
     * @notice Fills as much of the A offered as possible
     * @dev Heavily uses that internal functions are passing reference to memory structures
     * @param _self True if buying from "self" false otherwise.
     */
    function _useBOffer(
        RebalanceValues memory vars,
        Tick memory tick,
        bool _self
    ) internal pure {
        if (vars.offerBInA > 0 && tick.availableA > 0) {
            // Buying Asset A using Asset B
            uint128 amountASold = vars.offerBInA.toU128();
            if (vars.offerBInA > tick.availableA) {
                amountASold = tick.availableA;
            }
            // Underpays actual price if self, otherwise overpay (to not mess rounding)
            uint128 assetBPayment = denominateAssetAInB(amountASold, vars.currentPrice, !_self).toU128();

            tick.availableA -= amountASold.toU120();
            tick.assetAToB.sold += amountASold;
            tick.assetAToB.bought += assetBPayment;

            vars.offerBInA -= amountASold;
            vars.protocolSoldA += amountASold;
            vars.protocolBoughtB += assetBPayment;
        }
    }

    /**
     * @notice Computes the earliest tick where we had nothing available
     * @param _lastTickA The oldest tick with no available A
     * @param _lastTickB The oldest tick with no available B
     * @return The oldest tick with available assets
     */
    function _earliestUsedTick(uint256 _lastTickA, uint256 _lastTickB) internal pure returns (uint256) {
        uint256 start;
        if (_lastTickA == 0 && _lastTickB == 0) {
            revert("No deposits");
        } else if (_lastTickA * _lastTickB == 0) {
            // one are zero (the both case is handled explicitly above)
            start = _lastTickA > _lastTickB ? _lastTickA : _lastTickB;
        } else {
            start = _lastTickA < _lastTickB ? _lastTickA : _lastTickB;
        }
        return start;
    }
}
