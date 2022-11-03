// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IWETH} from "./../../interfaces/IWETH.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {IRollupProcessor} from "rollup-encoder/interfaces/IRollupProcessor.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {Ttoken} from "./../../interfaces/tokemak/Ttoken.sol";
import {IManager} from "./../../interfaces/tokemak/IManager.sol";

contract TokemakBridge is BridgeBase {
    using SafeERC20 for IERC20;

    struct Interaction {
        uint256 inputValue;
        address tAsset;
        uint256 nextNonce;
        uint256 previousNonce;
    }

    IWETH public constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    address public constant MANAGER = 0xA86e412109f77c45a3BC1c5870b880492Fb86A14;

    uint256 internal constant MAX_UINT = type(uint256).max;

    uint256 internal constant MIN_GAS_FOR_CHECK_AND_FINALISE = 83000;
    uint256 internal constant MIN_GAS_FOR_FUNCTION_COMPLETION = 5000;

    mapping(address => address) private tTokens;
    mapping(address => address) private assets;

    uint256 private lastProcessedNonce;

    uint256 private lastAddedNonce;

    uint256 private firstAddedNonce;

    // cache of all of our Defi interactions. keyed on _nonce
    mapping(uint256 => Interaction) public pendingInteractions;

    /**
     * @dev Constructor
     * @param _rollupProcessor the address of the rollup contract
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {
        loadTokens();
    }

    /**
     * @dev Function to add a new interaction to the bridge
     * Converts the amount of input asset given to the market determined amount of tranche asset
     * @param _inputAssetA The type of input asset for the new interaction
     * @param _outputAssetA The type of output asset for the new interaction
     * @param _totalInputValue The amount the the input asset provided in this interaction
     * @param _interactionNonce The _nonce value for this interaction
     * @param _auxData The expiry value for this interaction
     * @return outputValueA The interaction's first ouptut value after this call
     * @return outputValueB The interaction's second ouptut value after this call - will be 0
     * @return isAsync Flag specifying if this interaction is asynchronous
     */
    function convert(
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory,
        AztecTypes.AztecAsset memory _outputAssetA,
        AztecTypes.AztecAsset memory,
        uint256 _totalInputValue,
        uint256 _interactionNonce,
        uint64 _auxData,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256,
            bool isAsync
        )
    {
        // // ### INITIALIZATION AND SANITY CHECKS
        if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
            (bool success, ) = address(WETH).call{value: _totalInputValue}(abi.encodeWithSignature("deposit()"));
            if (success) {
                _inputAssetA.erc20Address = address(WETH);
                _inputAssetA.assetType = AztecTypes.AztecAssetType.ERC20;
            }
        }

        if (_inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert ErrorLib.InvalidInputA();
        if (_outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert ErrorLib.InvalidOutputA();

        // Check whether the call is for withdrawal or deposit
        bool isWithdrawal = _auxData != 0;

        address _tAsset = isWithdrawal ? _inputAssetA.erc20Address : tTokens[_inputAssetA.erc20Address];
        if (_tAsset == address(0)) revert ErrorLib.InvalidInput();

        if (isWithdrawal) {
            if (assets[_inputAssetA.erc20Address] != _outputAssetA.erc20Address) revert ErrorLib.InvalidInput();
            _addWithdrawalNonce(_interactionNonce, _tAsset, _totalInputValue);
            outputValueA = 0;
            isAsync = true;
        } else {
            if (tTokens[_inputAssetA.erc20Address] != _outputAssetA.erc20Address) revert ErrorLib.InvalidInput();

            outputValueA = _deposit(_tAsset, _totalInputValue);
        }
        _finalisePendingInteractions();

        return (outputValueA, 0, isAsync);
    }

    /**
     * @dev Function to finalise an interaction
     * Converts the held amount of tranche asset for the given interaction into the output asset
     * @param _interactionNonce The _nonce value for the interaction that should be finalised
     * @return outputValueA The interaction's first ouptut value after this call
     * @return outputValueB The interaction's second ouptut value after this call - will be 0
     * @return interactionCompleted Flag specifying if this interaction is completed
     */
    function finalise(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 _interactionNonce,
        uint64
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256,
            bool interactionCompleted
        )
    {
        // if (msg.sender != ROLLUP_PROCESSOR) revert ErrorLib.InvalidCaller();

        if (_inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert ErrorLib.InvalidInputA();
        if (_outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert ErrorLib.InvalidOutputA();

        address _tAsset = _inputAssetA.erc20Address;
        if (_tAsset == address(0)) revert ErrorLib.InvalidInputA();

        // Pending withdrawal value
        uint256 _inputValue = pendingInteractions[_interactionNonce].inputValue;
        if (_inputValue == 0) revert ErrorLib.InvalidInput();

        // Withdraw pending withdrawals
        (outputValueA, interactionCompleted) = _finaliseWithdraw(_tAsset, _inputValue, _interactionNonce);

        return (outputValueA, 0, interactionCompleted);
    }

    /**
     * @dev Function called to automatically fetch all the Pools from Tokemak Manager
     */
    function loadTokens() public {
        IManager _manager = IManager(MANAGER);
        address[] memory _pools = _manager.getPools();
        for (uint256 i = 0; i < _pools.length; i++) {
            address _pool = _pools[i];
            Ttoken _token = Ttoken(_pool);

            address _asset = _token.underlyer();
            IERC20 _assetToken = IERC20(_asset);

            _assetToken.approve(ROLLUP_PROCESSOR, MAX_UINT);
            _assetToken.approve(_pool, MAX_UINT);
            _token.approve(ROLLUP_PROCESSOR, MAX_UINT);
            _token.approve(_pool, MAX_UINT);

            tTokens[_asset] = _pool;
            assets[_pool] = _asset;
        }
    }

    /**
     * @dev Function to attempt finalising of as many interactions as possible within the specified gas limit
     * Continue checking for and finalising interactions until we expend the available gas
     */
    function _finalisePendingInteractions() internal {
        uint256 _gasFloor = MIN_GAS_FOR_FUNCTION_COMPLETION;
        // check and finalise interactions until we don't have enough gas left to reliably update our state without risk of reverting the entire transaction
        // gas left must be enough for check for next expiry, finalise and leave this function without breaching _gasFloor
        uint256 _gasLoopCondition = MIN_GAS_FOR_CHECK_AND_FINALISE + MIN_GAS_FOR_FUNCTION_COMPLETION + _gasFloor;
        uint256 _ourGasFloor = MIN_GAS_FOR_FUNCTION_COMPLETION + _gasFloor;
        while (gasleft() > _gasLoopCondition) {
            // check the heap to see if we can finalise an expired transaction
            // we provide a gas floor to the function which will enable us to leave this function without breaching our _gasFloor
            (bool _available, uint256 _nonce) = _getNextInteractionToFinalise(_ourGasFloor);
            if (!_available) {
                break;
            }
            // make sure we will have at least _ourGasFloor gas after the finalise in order to exit this function
            uint256 _gasRemaining = gasleft();
            if (_gasRemaining <= _ourGasFloor) {
                break;
            }
            uint256 _gasForFinalise = _gasRemaining - _ourGasFloor;
            // make the call to finalise the interaction with the gas limit
            try IRollupProcessor(ROLLUP_PROCESSOR).processAsyncDefiInteraction{gas: _gasForFinalise}(_nonce) returns (
                bool
            ) {
                // no need to do anything here, we just need to know that the call didn't throw
            } catch {
                break;
            }
        }
    }

    /**
     * @dev Function to get the next interaction to finalise
     * @param _gasFloor The amount of gas that needs to remain after this call has completed
     * @return expiryAvailable Flag specifying whether an expiry is available to be finalised
     * @return nonce The next interaction _nonce to be finalised
     */
    function _getNextInteractionToFinalise(uint256 _gasFloor)
        internal
        view
        returns (bool expiryAvailable, uint256 nonce)
    {
        // do we have any expiries and if so is the earliest expiry now expired
        uint256 _nonce = lastProcessedNonce;
        if (_nonce == 0 && firstAddedNonce != 0) {
            Interaction storage interaction = pendingInteractions[firstAddedNonce];
            if (interaction.inputValue != 0 && _canWithdraw(interaction.tAsset, interaction.inputValue)) {
                return (true, firstAddedNonce);
            }
            _nonce = firstAddedNonce;
        }

        if (pendingInteractions[_nonce].nextNonce == 0) {
            return (false, 0);
        }

        uint256 minGasForLoop = _gasFloor + MIN_GAS_FOR_CHECK_AND_FINALISE;
        while (pendingInteractions[_nonce].nextNonce != 0 && gasleft() >= minGasForLoop) {
            Interaction storage interaction = pendingInteractions[_nonce];
            if (interaction.inputValue == 0) {
                continue;
            }
            if (_canWithdraw(interaction.tAsset, interaction.inputValue)) {
                return (true, _nonce);
            }
            _nonce = pendingInteractions[_nonce].nextNonce;
        }

        return (false, 0);
    }

    /**
     * @dev Function to add withdrawal _nonce
     * @param _nonce Current _nonce
     * @param _tAsset The tokemak lp token used to withdraw
     * @param _inputValue Amount to withdraw
     */
    function _addWithdrawalNonce(
        uint256 _nonce,
        address _tAsset,
        uint256 _inputValue
    ) private {
        Ttoken tToken = Ttoken(_tAsset);
        tToken.requestWithdrawal(_inputValue);
        if (lastProcessedNonce == 0) {
            firstAddedNonce = _nonce;
        }
        pendingInteractions[_nonce] = Interaction(_inputValue, _tAsset, 0, lastAddedNonce);
        pendingInteractions[lastAddedNonce].nextNonce = _nonce;
        lastAddedNonce = _nonce;
    }

    /**
     * @dev Function to finalise a pending withdrawal
     * @param _tAsset The tokemak lp token used to withdraw
     * @param _nonce Current _nonce
     * @param _inputValue Amount to withdraw
     * @return outputValue Amount withdrawn
     * @return withdrawComplete bool is withdraw complete
     */
    function _finaliseWithdraw(
        address _tAsset,
        uint256 _inputValue,
        uint256 _nonce
    ) private returns (uint256 outputValue, bool withdrawComplete) {
        Ttoken tToken = Ttoken(_tAsset);

        if (!_canWithdraw(_tAsset, _inputValue)) {
            withdrawComplete = false;
            outputValue = 0;
            return (outputValue, withdrawComplete);
        }

        //Get asset address from tAsset
        address asset = assets[_tAsset];
        IERC20 assetToken = IERC20(asset);

        // Asset balance before withdrawal for calculating outputValue
        uint256 beforeBalance = assetToken.balanceOf(address(this));

        //Check if the pool is EthPool because withdrawal function is different
        if (asset == address(WETH)) {
            tToken.withdraw(_inputValue, false);
        } else {
            tToken.withdraw(_inputValue);
        }

        // Asset balance after withdrawal for calculating outputValue
        uint256 afterBalance = assetToken.balanceOf(address(this));

        outputValue = afterBalance - beforeBalance;
        uint256 previousNonce = pendingInteractions[_nonce].previousNonce;
        if (pendingInteractions[previousNonce].inputValue != 0) {
            pendingInteractions[previousNonce].nextNonce = pendingInteractions[_nonce].nextNonce;
        } else {
            lastProcessedNonce = _nonce;
        }
        withdrawComplete = true;
        delete pendingInteractions[_nonce];
    }

    /**
     * @dev Function to deposit in tokemak pool
     * @param _tAsset Tokemak pool to deposit
     * @param _inputValue Amount to withdraw
     * @return outputValue Output amount of tAsset after deposit
     */
    function _deposit(address _tAsset, uint256 _inputValue) private returns (uint256 outputValue) {
        Ttoken tToken = Ttoken(_tAsset);

        // Asset balance before withdrawal for calculating outputValue
        uint256 beforeBalance = tToken.balanceOf(address(this));

        //Deposit in Tokemak Pool
        tToken.deposit(_inputValue);

        // Asset balance after withdrawal for calculating outputValue
        uint256 balance = tToken.balanceOf(address(this));

        outputValue = balance - beforeBalance;
    }

    /**
     * @dev Function to check if we can withdraw
     * @param _tAsset The tokemak lp token used to withdraw
     * @param _inputValue Amount to withdraw
     * @return withdraw if we can withdraw boolean
     */
    function _canWithdraw(address _tAsset, uint256 _inputValue) private view returns (bool withdraw) {
        Ttoken tToken = Ttoken(_tAsset);

        // Get our current request withdrawal data
        (uint256 minCycle, uint256 requestedWithdrawalAmount) = tToken.requestedWithdrawals(address(this));

        // Get current cycle index
        uint256 currentCycleIndex = IManager(MANAGER).getCurrentCycleIndex();

        return (!(_inputValue > requestedWithdrawalAmount || currentCycleIndex < minCycle));
    }
}
