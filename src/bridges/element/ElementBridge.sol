// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IVault, IAsset, PoolSpecialization} from './interfaces/IVault.sol';
import {IPool} from './interfaces/IPool.sol';
import {ITranche} from './interfaces/ITranche.sol';
import {IDeploymentValidator} from './interfaces/IDeploymentValidator.sol';
import {IERC20Permit, IERC20} from '../../interfaces/IERC20Permit.sol';
import {IWrappedPosition} from './interfaces/IWrappedPosition.sol';
import {IRollupProcessor} from '../../interfaces/IRollupProcessor.sol';
import {MinHeap} from './MinHeap.sol';
import {FullMath} from '../uniswapv3/libraries/FullMath.sol';

import {IDefiBridge} from '../../interfaces/IDefiBridge.sol';

import {AztecTypes} from '../../aztec/AztecTypes.sol';

/**
 * @title Element Bridge
 * @dev Smart contract responsible for depositing, managing and redeeming Defi interactions with the Element protocol
 */

contract ElementBridge is IDefiBridge {
    using MinHeap for MinHeap.MinHeapData;

    /*----------------------------------------
      ERROR TAGS
      ----------------------------------------*/
    error INVALID_TRANCHE();
    error INVALID_WRAPPED_POSITION();
    error INVALID_POOL();
    error INVALID_CALLER();
    error ASSET_IDS_NOT_EQUAL();
    error ASSET_NOT_ERC20();
    error INTERACTION_ALREADY_EXISTS();
    error POOL_NOT_FOUND();
    error UNKNOWN_NONCE();
    error BRIDGE_NOT_READY();
    error ALREADY_FINALISED();
    error TRANCHE_POSITION_MISMATCH();
    error TRANCHE_UNDERLYING_MISMATCH();
    error POOL_UNDERLYING_MISMATCH();
    error POOL_EXPIRY_MISMATCH();
    error TRANCHE_EXPIRY_MISMATCH();
    error VAULT_ADDRESS_VERIFICATION_FAILED();
    error VAULT_ADDRESS_MISMATCH();
    error TRANCHE_ALREADY_EXPIRED();
    error UNREGISTERED_POOL();
    error UNREGISTERED_POSITION();
    error UNREGISTERED_PAIR();
    error INVALID_TOKEN_BALANCE_RECEIVED();
    error INVALID_CHANGE_IN_BALANCE();
    error RECEIVED_LESS_THAN_LIMIT();

    /*----------------------------------------
      STRUCTS
      ----------------------------------------*/
    /**
     * @dev Contains information that describes a specific interaction
     *
     * @param quantityPT the quantity of element principal tokens that were purchased by this interaction
     * @param trancheAddress the address of the element tranche for which principal tokens were purchased
     * @param expiry the time of expiry of this interaction's tranche
     * @param finalised flag specifying whether this interaction has been finalised
     * @param failed flag specifying whether this interaction failed to be finalised at any point
     */
    struct Interaction {
        uint256 quantityPT;
        address trancheAddress;
        uint64 expiry;
        bool finalised;
        bool failed;
    }

    /**
     * @dev Contains information that describes a specific element pool
     *
     * @param poolId the unique Id associated with the element pool
     * @param trancheAddress the address of the element tranche for which principal tokens are traded in the pool
     * @param poolAddress the address of the pool contract
     * @param wrappedPositionAddress the address of the underlying wrapped position token associated with the pool/tranche
     */
    struct Pool {
        bytes32 poolId;
        address trancheAddress;
        address poolAddress;
        address wrappedPositionAddress;
    }

    enum TrancheRedemptionStatus { NOT_REDEEMED, REDEMPTION_FAILED, REDEMPTION_SUCCEEDED }

    /**
     * @dev Contains information for managing all funds deposited/redeemed with a specific element tranche
     *
     * @param quantityTokensHeld total quantity of principal tokens purchased for the tranche
     * @param quantityAssetRedeemed total quantity of underlying tokens received from the element tranche on expiry
     * @param quantityAssetRemaining the current remainning quantity of underlying tokens held by the contract
     * @param numDeposits the total number of deposits (interactions) against the give tranche
     * @param numFinalised the current number of interactions against this tranche that have been finalised
     * @param redemptionStatus value describing the redemption status of the tranche
     */
    struct TrancheAccount {
        uint256 quantityTokensHeld;
        uint256 quantityAssetRedeemed;
        uint256 quantityAssetRemaining;
        uint32 numDeposits;
        uint32 numFinalised;
        TrancheRedemptionStatus redemptionStatus;
    }

    // Tranche factory address for Tranche contract address derivation
    address private immutable trancheFactory;
    // Tranche bytecode hash for Tranche contract address derivation.
    // This is constant as long as Tranche does not implement non-constant constructor arguments.
    bytes32 private immutable trancheBytecodeHash; // = 0xf481a073666136ab1f5e93b296e84df58092065256d0db23b2d22b62c68e978d;

    // cache of all of our Defi interactions. keyed on nonce
    mapping(uint256 => Interaction) public interactions;

    // cahce of all expiry values against the underlying asset address
    mapping(address => uint64[]) public assetToExpirys;

    // cache of all pools we have been configured to interact with
    mapping(uint256 => Pool) public pools;

    // cahce of all of our tranche accounts
    mapping(address => TrancheAccount) private trancheAccounts;

    // mapping containing the block number in which a tranche was configured
    mapping (address => uint256) private trancheDeploymentBlockNumbers;

    // the aztec rollup processor contract
    address public immutable rollupProcessor;

    // the balancer contract
    address private immutable balancerAddress;

    // the address of the element deployment validator contract
    address private immutable elementDeploymentValidatorAddress;

    // data structures used to manage the ongoing interaction deposit/redemption cycle
    MinHeap.MinHeapData private heap;
    mapping(uint64 => uint256[]) private expiryToNonce;

    // 48 hours in seconds, usd for calculating speeedbump expiries
    uint256 internal constant _FORTY_EIGHT_HOURS = 172800;

    uint256 internal constant MAX_UINT = type(uint256).max;

    uint256 internal constant MIN_GAS_FOR_CHECK_AND_FINALISE = 50000;
    uint256 internal constant MIN_GAS_FOR_FUNCTION_COMPLETION = 5000;
    uint256 internal constant MIN_GAS_FOR_FAILED_INTERACTION = 20000;
    uint256 internal constant MIN_GAS_FOR_EXPIRY_REMOVAL = 25000;

    // event emitted on every successful convert call
    event LogConvert(uint256 indexed nonce, uint256 totalInputValue, int64 gasUsed);

    // event emitted on every attempt to finalise, successful or otherwise
    event LogFinalise(uint256 indexed nonce, bool success, string message, int64 gasUsed);

    // event emitted on wvery newly configured pool
    event LogPoolAdded(address poolAddress, address wrappedPositionAddress, uint64 expiry);

    /**
     * @dev Constructor
     * @param _rollupProcessor the address of the rollup contract
     * @param _trancheFactory the address of the element tranche factor contract
     * @param _trancheBytecodeHash the hash of the bytecode of the tranche contract, used for tranche contract address derivation
     * @param _balancerVaultAddress the address of the balancer router contract
     * @param _elementDeploymentValidatorAddress the address of the element deployment validator contract
     */
    constructor(
        address _rollupProcessor,
        address _trancheFactory,
        bytes32 _trancheBytecodeHash,
        address _balancerVaultAddress,
        address _elementDeploymentValidatorAddress
    ) {
        rollupProcessor = _rollupProcessor;
        trancheFactory = _trancheFactory;
        trancheBytecodeHash = _trancheBytecodeHash;
        balancerAddress = _balancerVaultAddress;
        elementDeploymentValidatorAddress = _elementDeploymentValidatorAddress;
        heap.initialise(100);
    }

    /**
     * @dev Function for retrieving the available expiries for the given asset
     * @param asset the asset address being queried
     * @return assetExpiries the list of available expiries for the provided asset address
     */
    function getAssetExpiries(address asset) public view returns (uint64[] memory assetExpiries) {
        assetExpiries = assetToExpirys[asset];
    }

    /// @dev Registers a convergent pool with the contract, setting up a new asset/expiry element tranche
    /// @param _convergentPool The pool's address
    /// @param _wrappedPosition The element wrapped position contract's address
    /// @param _expiry The expiry of the tranche being configured
    function registerConvergentPoolAddress(
        address _convergentPool,
        address _wrappedPosition,
        uint64 _expiry
    ) external {
        checkAndStorePoolSpecification(_convergentPool, _wrappedPosition, _expiry);
    }

    /// @dev This internal function produces the deterministic create2
    ///      address of the Tranche contract from a wrapped position contract and expiry
    /// @param position The wrapped position contract address
    /// @param expiry The expiration time of the tranche as a uint256
    /// @return trancheContract derived Tranche contract address
    function deriveTranche(address position, uint256 expiry) internal view virtual returns (address trancheContract) {
        bytes32 salt = keccak256(abi.encodePacked(position, expiry));
        bytes32 addressBytes = keccak256(abi.encodePacked(bytes1(0xff), trancheFactory, salt, trancheBytecodeHash));
        trancheContract = address(uint160(uint256(addressBytes)));
    }

    struct PoolSpec {
        uint256 poolExpiry;
        bytes32 poolId;
        address underlyingAsset;
        address trancheAddress;
        address tranchePosition;
        address trancheUnderlying;
        address poolUnderlying;
        address poolVaultAddress;
    }

    /// @dev Validates and stores a convergent pool specification
    /// @param poolAddress The pool's address
    /// @param wrappedPositionAddress The element wrapped position contract's address
    /// @param expiry The expiry of the tranche being configured
    function checkAndStorePoolSpecification(
        address poolAddress,
        address wrappedPositionAddress,
        uint64 expiry        
    ) internal {
        PoolSpec memory poolSpec;
        IWrappedPosition wrappedPosition = IWrappedPosition(wrappedPositionAddress);
        // this underlying asset should be the real asset i.e. DAI stablecoin etc
        try wrappedPosition.token() returns (IERC20 wrappedPositionToken) {
            poolSpec.underlyingAsset = address(wrappedPositionToken);
        } catch {
            revert INVALID_WRAPPED_POSITION();
        }
        // this should be the address of the Element tranche for the asset/expiry pair
        poolSpec.trancheAddress = deriveTranche(wrappedPositionAddress, expiry);
        // get the wrapped position held in the tranche to cross check against that provided
        ITranche tranche = ITranche(poolSpec.trancheAddress);
        try tranche.position() returns (IERC20 tranchePositionToken) {
            poolSpec.tranchePosition = address(tranchePositionToken);
        } catch {
            revert INVALID_TRANCHE();
        }
        // get the underlying held in the tranche to cross check against that provided
        try tranche.underlying() returns (IERC20 trancheUnderlying) {
            poolSpec.trancheUnderlying = address(trancheUnderlying);
        } catch {
            revert INVALID_TRANCHE();
        }
        // get the tranche expiry to cross check against that provided
        uint64 trancheExpiry = 0;
        try tranche.unlockTimestamp() returns (uint256 trancheUnlock) {
            trancheExpiry = uint64(trancheUnlock);
        } catch {
            revert INVALID_TRANCHE();
        }
        if (trancheExpiry != expiry) {
            revert TRANCHE_EXPIRY_MISMATCH();
        }

        if (poolSpec.tranchePosition != wrappedPositionAddress) {
            revert TRANCHE_POSITION_MISMATCH();
        }
        if (poolSpec.trancheUnderlying != poolSpec.underlyingAsset) {
            revert TRANCHE_UNDERLYING_MISMATCH();
        }
        // get the pool underlying to cross check against that provided
        IPool pool = IPool(poolAddress);
        try pool.underlying() returns (IERC20 poolUnderlying) {
            poolSpec.poolUnderlying = address(poolUnderlying);
        } catch {
            revert INVALID_POOL();
        }
        // get the pool expiry to cross check against that provided
        try pool.expiration() returns (uint256 poolExpiry) {
            poolSpec.poolExpiry = poolExpiry;
        } catch {
            revert INVALID_POOL();
        }
        // get the vault associated with the pool
        try pool.getVault() returns (IVault poolVault) {
            poolSpec.poolVaultAddress = address(poolVault);
        } catch {
            revert INVALID_POOL();
        }
        // get the pool id associated with the pool
        try pool.getPoolId() returns (bytes32 poolId) {
            poolSpec.poolId = poolId;
        } catch {
            revert INVALID_POOL();
        }
        if (poolSpec.poolUnderlying != poolSpec.underlyingAsset) {
            revert POOL_UNDERLYING_MISMATCH();
        }
        if (poolSpec.poolExpiry != expiry) {
            revert POOL_EXPIRY_MISMATCH();
        }
        //verify that the vault address is equal to our balancer address
        if (poolSpec.poolVaultAddress != balancerAddress) {
            revert VAULT_ADDRESS_VERIFICATION_FAILED();
        }

        // retrieve the pool address for the given pool id from balancer
        // then test it against that given to us
        IVault balancerVault = IVault(balancerAddress);
        (address balancersPoolAddress, ) = balancerVault.getPool(poolSpec.poolId);
        if (poolAddress != balancersPoolAddress) {
            revert VAULT_ADDRESS_MISMATCH();
        }

        // verify with Element that the provided contracts are registered
        validatePositionAndPoolAddressesWithElementRegistry(wrappedPositionAddress, poolAddress);

        // we store the pool information against a hash of the asset and expiry
        uint256 assetExpiryHash = hashAssetAndExpiry(poolSpec.underlyingAsset, trancheExpiry);
        pools[assetExpiryHash] = Pool(poolSpec.poolId, poolSpec.trancheAddress, poolAddress, wrappedPositionAddress);
        uint64[] storage expiriesForAsset = assetToExpirys[poolSpec.underlyingAsset];
        uint256 expiryIndex = 0;
        while (expiryIndex < expiriesForAsset.length && expiriesForAsset[expiryIndex] != trancheExpiry) {
            ++expiryIndex;
        }
        if (expiryIndex == expiriesForAsset.length) {
            expiriesForAsset.push(trancheExpiry);
        }
        setTrancheDeploymentBlockNumber(poolSpec.trancheAddress);
        
        // initialising the expiry -> nonce mapping here like this reduces a chunk of gas later when we start to add interactions for this expiry
        uint256[] storage nonces = expiryToNonce[trancheExpiry];
        if (nonces.length == 0) {
            expiryToNonce[trancheExpiry].push(MAX_UINT);
        }
        emit LogPoolAdded(poolAddress, wrappedPositionAddress, trancheExpiry);
    }

    /**
    * @dev Sets the current block number as the block in which the given tranche was first configured
    * Only stores the block number if this is the first time this tranche has been configured
    * @param trancheAddress the address of the tranche against which to store the current block number
     */
    function setTrancheDeploymentBlockNumber(address trancheAddress) internal {
        uint256 trancheDeploymentBlock = trancheDeploymentBlockNumbers[trancheAddress];
        if (trancheDeploymentBlock == 0) {
            // only set the deployment block on the first time this tranche is configured
            trancheDeploymentBlockNumbers[trancheAddress] = block.number;
        }
    }

    /**
    * @dev Returns the block number in which a tranche was first configured on the bridge based on the nonce of an interaction in that tranche
    * @param interactionNonce the nonce of the interaction to query
    * @return blockNumber the number of the block in which the tranche was first configured
     */
    function getTrancheDeploymentBlockNumber(uint256 interactionNonce) public view returns (uint256 blockNumber) {
        Interaction storage interaction = interactions[interactionNonce];
        if (interaction.expiry == 0) {
            revert UNKNOWN_NONCE();
        }
        blockNumber = trancheDeploymentBlockNumbers[interaction.trancheAddress];
    }

    /**
    * @dev Verifies that the given pool and wrapped position addresses are registered in the Element deployment validator
    * Reverts if addresses don't validate successfully
    * @param wrappedPosition address of a wrapped position contract
    * @param pool address of a balancer pool contract
     */
    function validatePositionAndPoolAddressesWithElementRegistry(address wrappedPosition, address pool) internal {
        IDeploymentValidator validator = IDeploymentValidator(elementDeploymentValidatorAddress);
        if (!validator.checkPoolValidation(pool)) {
            revert UNREGISTERED_POOL();
        }
        if (!validator.checkWPValidation(wrappedPosition)) {
            revert UNREGISTERED_POSITION();
        }
        if (!validator.checkPairValidation(wrappedPosition, pool)) {
            revert UNREGISTERED_PAIR();
        }
    }

    /// @dev Produces a hash of the given asset and expiry value
    /// @param asset The asset address
    /// @param expiry The expiry value
    /// @return hashValue The resulting hash value
    function hashAssetAndExpiry(address asset, uint64 expiry) public pure returns (uint256 hashValue) {
        hashValue = uint256(keccak256(abi.encodePacked(asset, uint256(expiry))));
    }

    struct ConvertArgs {
        address inputAssetAddress;
        uint256 totalInputValue;
        uint256 interactionNonce;
        uint64 auxData;
    }

    /**
     * @dev Function to add a new interaction to the bridge
     * Converts the amount of input asset given to the market determined amount of tranche asset
     * @param inputAssetA The type of input asset for the new interaction
     * @param outputAssetA The type of output asset for the new interaction
     * @param totalInputValue The amount the the input asset provided in this interaction
     * @param interactionNonce The nonce value for this interaction
     * @param auxData The expiry value for this interaction
     * @return outputValueA The interaction's first ouptut value after this call - will be 0
     * @return outputValueB The interaction's second ouptut value after this call - will be 0
     * @return isAsync Flag specifying if this interaction is asynchronous - will be true
     */
    function convert(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 totalInputValue,
        uint256 interactionNonce,
        uint64 auxData,
        address
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
        int64 gasAtStart = int64(int256(gasleft()));
        int64 gasUsed = 0;
        // ### INITIALIZATION AND SANITY CHECKS
        if (msg.sender != rollupProcessor) {
            revert INVALID_CALLER();
        }
        if (inputAssetA.id != outputAssetA.id) {
            revert ASSET_IDS_NOT_EQUAL();
        }
        if (inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) {
            revert ASSET_NOT_ERC20();
        }
        if (interactions[interactionNonce].expiry != 0) {
            revert INTERACTION_ALREADY_EXISTS();
        }
        
        // operation is asynchronous
        isAsync = true;
        outputValueA = 0;
        outputValueB = 0;

        // capture the proficed arguments in a struct to prevent 'stack too deep' errors
        ConvertArgs memory convertArgs = ConvertArgs({
            inputAssetAddress: inputAssetA.erc20Address,
            totalInputValue: totalInputValue,
            interactionNonce: interactionNonce,
            auxData: auxData
        });

        // retrieve the appropriate pool for this interaction and verify that it exists
        Pool storage pool = pools[hashAssetAndExpiry(convertArgs.inputAssetAddress, convertArgs.auxData)];
        if (pool.trancheAddress == address(0)) {
            revert POOL_NOT_FOUND();
        }
        ITranche tranche = ITranche(pool.trancheAddress);
        uint64 trancheExpiry = uint64(tranche.unlockTimestamp());
        if (block.timestamp >= trancheExpiry) {
            revert TRANCHE_ALREADY_EXPIRED();
        }
        
        // approve the transfer of tokens to the balancer address
        ERC20(convertArgs.inputAssetAddress).approve(balancerAddress, convertArgs.totalInputValue);
        // execute the swap on balancer
        uint256 principalTokensAmount = exchangeAssetForTrancheTokens(convertArgs.inputAssetAddress, pool, convertArgs.totalInputValue);
        // store the tranche that underpins our interaction, the expiry and the number of received tokens against the nonce
        Interaction storage newInteraction = interactions[convertArgs.interactionNonce];
        newInteraction.expiry = trancheExpiry;
        newInteraction.failed = false;
        newInteraction.finalised = false;
        newInteraction.quantityPT = principalTokensAmount;
        newInteraction.trancheAddress = pool.trancheAddress;
        // add the nonce and expiry to our expiry heap
        addNonceAndExpiryToNonceMapping(convertArgs.interactionNonce, trancheExpiry);
        // increase our tranche account deposits and holdings
        // other members are left as their initial values (all zeros)
        TrancheAccount storage trancheAccount = trancheAccounts[newInteraction.trancheAddress];
        trancheAccount.numDeposits++;
        trancheAccount.quantityTokensHeld += newInteraction.quantityPT;
        unchecked { gasUsed = gasAtStart - int64(int256(gasleft())); }
        emit LogConvert(convertArgs.interactionNonce, convertArgs.totalInputValue, gasUsed);
        finaliseExpiredInteractions(MIN_GAS_FOR_FUNCTION_COMPLETION);
        // we need to get here with MIN_GAS_FOR_FUNCTION_COMPLETION gas to exit.
    }

    /** 
    * @dev Function to exchange the input asset for tranche tokens on Balancer
    * @param inputAsset the address of the asset we want to swap
    * @param pool storage struct containing details of the pool we wish to use for the swap
    * @param inputQuantity the quantity of the input asset we wish to swap
    * @return quantityReceived amount of tokens recieved
    */
    function exchangeAssetForTrancheTokens(address inputAsset, Pool storage pool, uint256 inputQuantity) internal returns (uint256 quantityReceived) {
        IVault.SingleSwap memory singleSwap = IVault.SingleSwap({
            poolId: pool.poolId, // the id of the pool we want to use
            kind: IVault.SwapKind.GIVEN_IN, // We are exchanging a given number of input tokens
            assetIn: IAsset(inputAsset), // the input asset for the swap
            assetOut: IAsset(pool.trancheAddress), // the tranche token address as the output asset
            amount: inputQuantity, // the total amount of input asset we wish to swap
            userData: '0x00' // set to 0 as per the docs, this is unused in current balancer pools
        });
        IVault.FundManagement memory fundManagement = IVault.FundManagement({
            sender: address(this), // the bridge has already received the tokens from the rollup so it owns totalInputValue of inputAssetA
            fromInternalBalance: false,
            recipient: payable(address(this)), // we want the output tokens transferred back to us
            toInternalBalance: false
        });

        uint256 trancheTokenQuantityBefore = ERC20(pool.trancheAddress).balanceOf(address(this));
        quantityReceived = IVault(balancerAddress).swap(
            singleSwap,
            fundManagement,
            inputQuantity, // we won't accept less than 1 output token per input token
            block.timestamp
        );

        uint256 trancheTokenQuantityAfter = ERC20(pool.trancheAddress).balanceOf(address(this));
        // ensure we haven't lost tokens!
        if (trancheTokenQuantityAfter < trancheTokenQuantityBefore) {
            revert INVALID_CHANGE_IN_BALANCE();
        }
        // change in balance must be >= 0 here
        uint256 changeInBalance = trancheTokenQuantityAfter - trancheTokenQuantityBefore;
        // ensure the change in balance matches that reported to us
        if (changeInBalance != quantityReceived) {
            revert INVALID_TOKEN_BALANCE_RECEIVED();
        }
        // ensure we received at least the limit we placed
        if (quantityReceived < inputQuantity) {
            revert RECEIVED_LESS_THAN_LIMIT();
        }
    }

    /**
     * @dev Function to attempt finalising of as many interactions as possible within the specified gas limit
     * Continue checking for and finalising interactions until we expend the available gas
     * @param gasFloor The amount of gas that needs to remain after this call has completed
     */
    function finaliseExpiredInteractions(uint256 gasFloor) internal {
        // check and finalise interactions until we don't have enough gas left to reliably update our state without risk of reverting the entire transaction
        // gas left must be enough for check for next expiry, finalise and leave this function without breaching gasFloor
        uint256 gasLoopCondition = MIN_GAS_FOR_CHECK_AND_FINALISE + MIN_GAS_FOR_FUNCTION_COMPLETION + gasFloor;
        uint256 ourGasFloor = MIN_GAS_FOR_FUNCTION_COMPLETION + gasFloor;
        while (gasleft() > gasLoopCondition) {
            // check the heap to see if we can finalise an expired transaction
            // we provide a gas floor to the function which will enable us to leave this function without breaching our gasFloor
            (bool expiryAvailable, uint256 nonce) = checkForNextInteractionToFinalise(ourGasFloor);
            if (!expiryAvailable) {
                break;
            }
            // make sure we will have at least ourGasFloor gas after the finalise in order to exit this function
            uint256 gasRemaining = gasleft();
            if (gasRemaining <= ourGasFloor) {
                break;
            }
            uint256 gasForFinalise = gasRemaining - ourGasFloor;
            // make the call to finalise the interaction with the gas limit        
            try IRollupProcessor(rollupProcessor).processAsyncDefiInteraction{gas: gasForFinalise}(nonce) returns (bool interactionCompleted) {
                // no need to do anything here, we just need to know that the call didn't throw
            } catch {
                break;
            }
        }
    }

    /**
     * @dev Function to finalise an interaction
     * Converts the held amount of tranche asset for the given interaction into the output asset
     * @param interactionNonce The nonce value for the interaction that should be finalised
     */
    function finalise(
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata,
        uint256 interactionNonce,
        uint64
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
        int64 gasAtStart = int64(int256(gasleft()));
        int64 gasUsed = 0;
        if (msg.sender != rollupProcessor) {
            revert INVALID_CALLER();
        }
        // retrieve the interaction and verify it's ready for finalising
        Interaction storage interaction = interactions[interactionNonce];
        if (interaction.expiry == 0) {
            revert UNKNOWN_NONCE();
        }
        if (interaction.expiry > block.timestamp) {
            revert BRIDGE_NOT_READY();
        }
        if (interaction.finalised) {
            revert ALREADY_FINALISED();
        }

        TrancheAccount storage trancheAccount = trancheAccounts[interaction.trancheAddress];
        if (trancheAccount.numDeposits == 0) {
            // shouldn't be possible, this means we have had no deposits against this tranche
            setInteractionAsFailure(interaction, interactionNonce, 'NO_DEPOSITS_FOR_TRANCHE', 0);
            popInteractionFromNonceMapping(interaction, interactionNonce);
            return (0, 0, false);
        }

        // we only want to redeem the tranche if it hasn't previously successfully been redeemed
        if (trancheAccount.redemptionStatus != TrancheRedemptionStatus.REDEMPTION_SUCCEEDED) {
            // tranche not redeemed, we need to withdraw the principal
            // convert the tokens back to underlying using the tranche
            ITranche tranche = ITranche(interaction.trancheAddress);
            try tranche.withdrawPrincipal(trancheAccount.quantityTokensHeld, address(this)) returns (uint256 valueRedeemed) {
                trancheAccount.quantityAssetRedeemed = valueRedeemed;
                trancheAccount.quantityAssetRemaining = valueRedeemed;
                trancheAccount.redemptionStatus = TrancheRedemptionStatus.REDEMPTION_SUCCEEDED;
            } catch Error(string memory errorMessage) {
                unchecked { gasUsed = gasAtStart - int64(int256(gasleft())); }
                setInteractionAsFailure(interaction, interactionNonce, errorMessage, gasUsed);
                trancheAccount.redemptionStatus = TrancheRedemptionStatus.REDEMPTION_FAILED;
                popInteractionFromNonceMapping(interaction, interactionNonce);
                return (0, 0, false);
            } catch {
                unchecked { gasUsed = gasAtStart - int64(int256(gasleft())); }
                setInteractionAsFailure(interaction, interactionNonce, 'UNKNOWN_ERROR_FROM_TRANCHE_WITHDRAW', gasUsed);
                trancheAccount.redemptionStatus = TrancheRedemptionStatus.REDEMPTION_FAILED;
                popInteractionFromNonceMapping(interaction, interactionNonce);
                return (0, 0, false);
            }
        }

        // at this point, the tranche must have been redeemed and we can allocate proportionately to this interaction
        uint256 amountToAllocate = 0;
        if (trancheAccount.quantityTokensHeld == 0) {
            // what can we do here? 
            // we seem to have 0 total principle tokens so we can't apportion the output asset as it must be the case that each interaction purchased 0
            // we know that the number of deposits against this tranche is > 0 as we check further up this function
            // so we will have to divide the output asset, if there is any, equally
            amountToAllocate = trancheAccount.quantityAssetRedeemed / trancheAccount.numDeposits;
        } else {
            // apportion the output asset based on the interaction's holding of the principle token
            // protects against phantom overflow in the operation of
            // amountToAllocate = (trancheAccount.quantityAssetRedeemed * interaction.quantityPT) / trancheAccount.quantityTokensHeld;
            amountToAllocate = FullMath.mulDiv(trancheAccount.quantityAssetRedeemed, interaction.quantityPT, trancheAccount.quantityTokensHeld);
        }
        // numDeposits and numFinalised are uint32 types, so easily within range for an int256
        int256 numRemainingInteractionsForTranche = int256(uint256(trancheAccount.numDeposits)) - int256(uint256(trancheAccount.numFinalised));
        // the number of remaining interactions should never be less than 1 here, but test for <= 1 to ensure we catch all possibilities
        if (numRemainingInteractionsForTranche <= 1 || amountToAllocate > trancheAccount.quantityAssetRemaining) {
            // if there are no more interactions to finalise after this then allocate all the remaining
            // likewise if we have managed to allocate more than the remaining
            amountToAllocate = trancheAccount.quantityAssetRemaining;
        }
        trancheAccount.quantityAssetRemaining -= amountToAllocate;
        trancheAccount.numFinalised++;

        // approve the transfer of funds back to the rollup contract
        ERC20(outputAssetA.erc20Address).approve(rollupProcessor, amountToAllocate);
        interaction.finalised = true;
        popInteractionFromNonceMapping(interaction, interactionNonce);
        outputValueA = amountToAllocate;
        outputValueB = 0;
        interactionCompleted = true;
        unchecked { gasUsed = gasAtStart - int64(int256(gasleft())); }
        emit LogFinalise(interactionNonce, interactionCompleted, '', gasUsed);
    }

    /**
     * @dev Function to mark an interaction as having failed and publish a finalise event
     * @param interaction The interaction that failed
     * @param interactionNonce The nonce of the failed interaction
     * @param message The reason for failure
     */
    function setInteractionAsFailure(
        Interaction storage interaction,
        uint256 interactionNonce,
        string memory message,
        int64 gasUsed
    ) internal {
        interaction.failed = true;
        emit LogFinalise(interactionNonce, false, message, gasUsed);
    }

    /**
     * @dev Function to add an interaction nonce and expiry to the heap data structures
     * @param nonce The nonce of the interaction to be added
     * @param expiry The expiry of the interaction to be added
     * @return expiryAdded Flag specifying whether the interactions expiry was added to the heap
     */
    function addNonceAndExpiryToNonceMapping(uint256 nonce, uint64 expiry) internal returns (bool expiryAdded) {
        // get the set of nonces already against this expiry
        // check for the MAX_UINT placeholder nonce that exists to reduce gas costs at this point in the code
        expiryAdded = false;
        uint256[] storage nonces = expiryToNonce[expiry];
        if (nonces.length == 1 && nonces[0] == MAX_UINT) {
            nonces[0] = nonce;
        } else {
            nonces.push(nonce);
        }
        // is this the first time this expiry has been requested?
        // if so then add it to our expiry heap
        if (nonces.length == 1) {
            heap.add(expiry);
            expiryAdded = true;
        }
    }

    /**
     * @dev Function to remove an interaction from the heap data structures
     * @param interaction The interaction should be removed
     * @param interactionNonce The nonce of the interaction to be removed
     * @return expiryRemoved Flag specifying whether the interactions expiry was removed from the heap
     */
    function popInteractionFromNonceMapping(Interaction storage interaction, uint256 interactionNonce) internal returns (bool expiryRemoved) {
        uint256[] storage nonces = expiryToNonce[interaction.expiry];
        if (nonces.length == 0) {
            return (false);
        }
        uint256 index = nonces.length - 1;
        while (index > 0 && nonces[index] != interactionNonce) {
            --index;
        }
        if (nonces[index] != interactionNonce) {
            return (false);
        }
        if (index != nonces.length - 1) {
            nonces[index] = nonces[nonces.length - 1];
        }
        nonces.pop();

        // if there are no more nonces left for this expiry then remove it from the heap
        if (nonces.length == 0) {
            heap.remove(interaction.expiry);
            delete expiryToNonce[interaction.expiry];
            return (true);
        }
        return (false);
    }

    /**
     * @dev Function to determine if we are able to finalise an interaction
     * @param gasFloor The amount of gas that needs to remain after this call has completed
     * @return expiryAvailable Flag specifying whether an expiry is available to be finalised
     * @return nonce The next interaction nonce to be finalised
     */
    function checkForNextInteractionToFinalise(uint256 gasFloor)
        internal
        returns (
            bool expiryAvailable,
            uint256 nonce
        )
    {
        // do we have any expiries and if so is the earliest expiry now expired
        if (heap.size() == 0) {
            return (false, 0);
        }
        // retrieve the minimum (oldest) expiry and determine if it is in the past
        uint64 nextExpiry = heap.min();
        if (nextExpiry > block.timestamp) {
            // oldest expiry is still not expired
            return (false, 0);
        }
        // we have some expired interactions
        uint256[] storage nonces = expiryToNonce[nextExpiry];
        uint256 minGasForLoop = (gasFloor + MIN_GAS_FOR_FAILED_INTERACTION);
        while (nonces.length > 0 && gasleft() >= minGasForLoop) {
            uint256 nextNonce = nonces[nonces.length - 1];
            if (nextNonce == MAX_UINT) {
                // this shouldn't happen, this value is the placeholder for reducing gas costs on convert
                // we just need to pop and continue
                nonces.pop();
                continue;
            }
            Interaction storage interaction = interactions[nextNonce];
            if (interaction.expiry == 0 || interaction.finalised || interaction.failed) {
                // this shouldn't happen, suggests the interaction has been finalised already but not removed from the sets of nonces for this expiry
                // remove the nonce and continue searching
                nonces.pop();
                continue;
            }
            // we have valid interaction for the next expiry, check if it can be finalised
            (bool canBeFinalised, string memory message) = interactionCanBeFinalised(interaction);
            if (!canBeFinalised) {
                // can't be finalised, add to failures and pop from nonces
                setInteractionAsFailure(interaction, nextNonce, message, 0);
                nonces.pop();
                continue;
            }
            return (true, nextNonce);
        }

        // if we don't have enough gas to remove the expiry, it will be removed next time
        if (nonces.length == 0 && gasleft() >= (gasFloor + MIN_GAS_FOR_EXPIRY_REMOVAL)) {
            // if we are here then we have run out of nonces for this expiry so pop from the heap
            heap.remove(nextExpiry);
        }
        return (false, 0);
    }

    /**
     * @dev Determine if an interaction can be finalised
     * Performs a variety of check on the tranche and tranche account to determine 
     * a. if the tranche has already been redeemed
     * b. if the tranche is currently under a speedbump
     * c. if the yearn vault has sufficient balance to support tranche redemption
     * @param interaction The interaction to be finalised
     * @return canBeFinalised Flag specifying whether the interaction can be finalised
     * @return message Message value giving the reason why an interaction can't be finalised
     */
    function interactionCanBeFinalised(Interaction storage interaction) internal returns (bool canBeFinalised, string memory message) {
        TrancheAccount storage trancheAccount = trancheAccounts[interaction.trancheAddress];
        if (trancheAccount.numDeposits == 0) {
            // shouldn't happen, suggests we don't have an account for this tranche!
            return (false, 'NO_DEPOSITS_FOR_TRANCHE');
        }
        if (trancheAccount.redemptionStatus == TrancheRedemptionStatus.REDEMPTION_FAILED) {
            return (false, 'TRANCHE_REDEMPTION_FAILED');
        }
        // determine if the tranche has already been redeemed
        if (trancheAccount.redemptionStatus == TrancheRedemptionStatus.REDEMPTION_SUCCEEDED) {
            // tranche was previously redeemed
            if (trancheAccount.quantityAssetRemaining == 0) {
                // this is a problem. we have already allocated out all of the redeemed assets!
                return (false, 'ASSET_ALREADY_FULLY_ALLOCATED');
            }
            // this interaction can be finalised. we don't need to redeem the tranche, we just need to allocate the redeemed asset
            return (true, '');
        }
        // tranche hasn't been redeemed, now check to see if we can redeem it
        ITranche tranche = ITranche(interaction.trancheAddress);
        uint256 speedbump = tranche.speedbump();
        if (speedbump != 0) {
            uint256 newExpiry = speedbump + _FORTY_EIGHT_HOURS;
            if (newExpiry > block.timestamp) {
                // a speedbump is in force for this tranche and it is beyond the current time
                trancheAccount.redemptionStatus = TrancheRedemptionStatus.REDEMPTION_FAILED;
                return (false, 'SPEEDBUMP');
            }
        }
        address wpAddress = address(tranche.position());
        IWrappedPosition wrappedPosition = IWrappedPosition(wpAddress);
        address underlyingAddress = address(wrappedPosition.token());
        address yearnVaultAddress = address(wrappedPosition.vault());
        uint256 vaultQuantity = ERC20(underlyingAddress).balanceOf(yearnVaultAddress);
        if (trancheAccount.quantityTokensHeld > vaultQuantity) {
            trancheAccount.redemptionStatus = TrancheRedemptionStatus.REDEMPTION_FAILED;
            return (false, 'VAULT_BALANCE');
        }
        // at this point, we will need to redeem the tranche which should be possible
        return (true, '');
    }
}
