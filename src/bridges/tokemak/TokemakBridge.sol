// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IDefiBridge} from "../../aztec/interfaces/IDefiBridge.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";

import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";

interface Ttoken is IERC20 {
    function requestedWithdrawals(address account) external view returns (uint256, uint256);

    function requestWithdrawal(uint256 amount) external;

    function deposit(uint256 amount) external payable;

    function withdraw(uint256 requestedAmount) external;

    function withdraw(uint256 requestedAmount, bool asEth) external;

    function underlyer() external view returns (address);
}

interface IManager {
    function getCurrentCycleIndex() external view returns (uint256);

    function getPools() external view returns (address[] memory);
}

contract TokemakBridge is IDefiBridge {
    using SafeERC20 for IERC20;

    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    address public constant MANAGER = 0xA86e412109f77c45a3BC1c5870b880492Fb86A14;

    address public immutable rollupProcessor;

    uint256 internal constant MAX_UINT = type(uint256).max;

    uint256 internal constant MIN_GAS_FOR_CHECK_AND_FINALISE = 83000;
    uint256 internal constant MIN_GAS_FOR_FUNCTION_COMPLETION = 5000;

    mapping(address => address) tTokens;
    mapping(address => address) assets;

    error InvalidCaller();
    error InvalidAssetType();
    error InvalidAsset(address token);
    error InvalidInput();

    struct Interaction {
        uint256 inputValue;
        address tAsset;
        uint256 nextNonce;
        uint256 previousNonce;
    }

    uint256 lastProcessedNonce;

    uint256 lastAddedNonce;

    uint256 firstAddedNonce;

    // cache of all of our Defi interactions. keyed on nonce
    mapping(uint256 => Interaction) public pendingInteractions;

    constructor(address _rollupProcessor) public {
        rollupProcessor = _rollupProcessor;
        loadTokens();
    }

    function convert(
        AztecTypes.AztecAsset memory inputAssetA,
        AztecTypes.AztecAsset memory inputAssetB,
        AztecTypes.AztecAsset memory outputAssetA,
        AztecTypes.AztecAsset memory outputAssetB,
        uint256 totalInputValue,
        uint256 interactionNonce,
        uint64 auxData,
        address rollupBeneficiary
    )
        external
        payable
        override
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        )
    {
        // // ### INITIALIZATION AND SANITY CHECKS
        if (msg.sender != rollupProcessor) revert InvalidCaller();
        if (inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert InvalidAssetType();
        if (outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert InvalidAssetType();

        // Check whether the call is for withdrawal or deposit
        bool isWithdrawal = auxData != 0;

        if (isWithdrawal) {
            if (assets[inputAssetA.erc20Address] != outputAssetA.erc20Address)
                revert InvalidAsset(inputAssetA.erc20Address);
        } else {
            if (tTokens[inputAssetA.erc20Address] != outputAssetA.erc20Address)
                revert InvalidAsset(inputAssetA.erc20Address);
        }

        address tAsset = isWithdrawal ? inputAssetA.erc20Address : tTokens[inputAssetA.erc20Address];

        if (tAsset == address(0)) revert InvalidAsset(tAsset);

        // Withdraw or Deposit
        if (isWithdrawal) {
            isAsync = true;
            outputValueA = 0;
            addWithdrawalNonce(interactionNonce, tAsset, totalInputValue);
        } else {
            isAsync = false;
            outputValueA = deposit(tAsset, totalInputValue, inputAssetA.erc20Address);
        }

        finalisePendingInteractions(MIN_GAS_FOR_FUNCTION_COMPLETION);
    }

    function finalise(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 interactionNonce,
        uint64 auxData
    )
        external
        payable
        override
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool interactionCompleted
        )
    {
        if (msg.sender != rollupProcessor) revert InvalidCaller();
        if (inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert InvalidAssetType();
        if (outputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert InvalidAssetType();

        // Pending withdrawal value
        uint256 inputValue = pendingInteractions[interactionNonce].inputValue;
        if (inputValue <= 0) revert InvalidInput();

        address tAsset = inputAssetA.erc20Address;
        if (tAsset == address(0)) revert InvalidAsset(tAsset);
        // Withdraw pending withdrawals
        (outputValueA, interactionCompleted) = finaliseWithdraw(tAsset, inputValue, interactionNonce);
    }

    function loadTokens() public {
        IManager manager = IManager(MANAGER);
        address[] memory pools = manager.getPools();
        for (uint256 i = 0; i < pools.length; i++) {
            address pool = pools[i];
            Ttoken token = Ttoken(pool);

            address asset = token.underlyer();
            IERC20 assetToken = IERC20(asset);

            assetToken.approve(rollupProcessor, MAX_UINT);
            assetToken.approve(pool, MAX_UINT);
            token.approve(rollupProcessor, MAX_UINT);
            token.approve(pool, MAX_UINT);

            tTokens[asset] = pool;
            assets[pool] = asset;
        }
    }

    /**
     * @dev Function to attempt finalising of as many interactions as possible within the specified gas limit
     * Continue checking for and finalising interactions until we expend the available gas
     * @param gasFloor The amount of gas that needs to remain after this call has completed
     */
    function finalisePendingInteractions(uint256 gasFloor) internal {
        // check and finalise interactions until we don't have enough gas left to reliably update our state without risk of reverting the entire transaction
        // gas left must be enough for check for next expiry, finalise and leave this function without breaching gasFloor
        uint256 gasLoopCondition = MIN_GAS_FOR_CHECK_AND_FINALISE + MIN_GAS_FOR_FUNCTION_COMPLETION + gasFloor;
        uint256 ourGasFloor = MIN_GAS_FOR_FUNCTION_COMPLETION + gasFloor;
        while (gasleft() > gasLoopCondition) {
            // check the heap to see if we can finalise an expired transaction
            // we provide a gas floor to the function which will enable us to leave this function without breaching our gasFloor
            (bool available, uint256 nonce) = checkForNextInteractionToFinalise(ourGasFloor);
            if (!available) {
                break;
            }
            // make sure we will have at least ourGasFloor gas after the finalise in order to exit this function
            uint256 gasRemaining = gasleft();
            if (gasRemaining <= ourGasFloor) {
                break;
            }
            uint256 gasForFinalise = gasRemaining - ourGasFloor;
            // make the call to finalise the interaction with the gas limit
            try IRollupProcessor(rollupProcessor).processAsyncDefiInteraction{gas: gasForFinalise}(nonce) returns (
                bool interactionCompleted
            ) {
                // no need to do anything here, we just need to know that the call didn't throw
            } catch {
                break;
            }
        }
    }

    /**
     * @dev Function to get the next interaction to finalise
     * @param gasFloor The amount of gas that needs to remain after this call has completed
     */
    function checkForNextInteractionToFinalise(uint256 gasFloor) internal returns (bool, uint256) {
        // do we have any expiries and if so is the earliest expiry now expired
        uint256 nonce = lastProcessedNonce;
        if (nonce == 0 && firstAddedNonce != 0) {
            Interaction storage interaction = pendingInteractions[firstAddedNonce];
            if (interaction.inputValue != 0 && canWithdraw(interaction.tAsset, interaction.inputValue)) {
                return (true, firstAddedNonce);
            }
            nonce = firstAddedNonce;
        }

        if (pendingInteractions[nonce].nextNonce == 0) {
            return (false, 0);
        }

        uint256 minGasForLoop = gasFloor + MIN_GAS_FOR_CHECK_AND_FINALISE;
        while (pendingInteractions[nonce].nextNonce != 0 && gasleft() >= minGasForLoop) {
            Interaction storage interaction = pendingInteractions[nonce];
            if (interaction.inputValue == 0) {
                continue;
            }
            if (canWithdraw(interaction.tAsset, interaction.inputValue)) {
                return (true, nonce);
            }
            nonce = pendingInteractions[nonce].nextNonce;
        }

        return (false, 0);
    }

    function canWithdraw(address tAsset, uint256 inputValue) private returns (bool) {
        Ttoken tToken = Ttoken(tAsset);

        // Get our current request withdrawal data
        (uint256 minCycle, uint256 requestedWithdrawalAmount) = tToken.requestedWithdrawals(address(this));

        // Get current cycle index
        uint256 currentCycleIndex = IManager(MANAGER).getCurrentCycleIndex();

        return (!(inputValue > requestedWithdrawalAmount || currentCycleIndex < minCycle));
    }

    function addWithdrawalNonce(
        uint256 nonce,
        address tAsset,
        uint256 inputValue
    ) private returns (uint256, bool) {
        Ttoken tToken = Ttoken(tAsset);
        tToken.requestWithdrawal(inputValue);
        if (lastProcessedNonce == 0) {
            firstAddedNonce = nonce;
        }
        pendingInteractions[nonce] = Interaction(inputValue, tAsset, 0, lastAddedNonce);
        pendingInteractions[lastAddedNonce].nextNonce = nonce;
        lastAddedNonce = nonce;
        return (0, true);
    }

    function finaliseWithdraw(
        address tAsset,
        uint256 inputValue,
        uint256 nonce
    ) private returns (uint256 outputValue, bool withdrawComplete) {
        Ttoken tToken = Ttoken(tAsset);

        if (!canWithdraw(tAsset, inputValue)) {
            withdrawComplete = false;
            outputValue = 0;
            return (outputValue, withdrawComplete);
        }

        //Get asset address from tAsset
        address asset = assets[tAsset];
        IERC20 assetToken = IERC20(asset);

        // Asset balance before withdrawal for calculating outputValue
        uint256 beforeBalance = assetToken.balanceOf(address(this));

        //Check if the pool is EthPool because withdrawal function is different
        if (asset == WETH) {
            tToken.withdraw(inputValue, false);
        } else {
            tToken.withdraw(inputValue);
        }

        // Asset balance after withdrawal for calculating outputValue
        uint256 afterBalance = assetToken.balanceOf(address(this));

        outputValue = afterBalance - beforeBalance;
        uint256 previousNonce = pendingInteractions[nonce].previousNonce;
        if (pendingInteractions[previousNonce].inputValue != 0) {
            pendingInteractions[previousNonce].nextNonce = pendingInteractions[nonce].nextNonce;
        } else {
            lastProcessedNonce = nonce;
        }

        delete pendingInteractions[nonce];
    }

    function deposit(
        address tAsset,
        uint256 inputValue,
        address asset
    ) private returns (uint256 outputValue) {
        Ttoken tToken = Ttoken(tAsset);

        // Asset balance before withdrawal for calculating outputValue
        uint256 beforeBalance = tToken.balanceOf(address(this));

        //Deposit in Tokemak Pool
        tToken.deposit(inputValue);

        // Asset balance after withdrawal for calculating outputValue
        uint256 afterBalance = tToken.balanceOf(address(this));

        // Output Value
        outputValue = afterBalance - beforeBalance;
    }
}
