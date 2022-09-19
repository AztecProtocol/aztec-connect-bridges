// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test, Vm} from "forge-std/Test.sol";
import {AztecTypes} from "./../../../aztec/libraries/AztecTypes.sol";
import {IRollupProcessor} from "./../../../aztec/interfaces/IRollupProcessor.sol";
import {ISubsidy} from "../../../aztec/interfaces/ISubsidy.sol";

/**
 * @notice Helper contract that allow us to test bridges against the live rollup by sending mock rollups with defi interactions
 *         The helper will setup the state and impersonate parties to allow easy interaction with the rollup
 * @author Lasse Herskind
 */
abstract contract BridgeTestBase is Test {
    /* solhint-disable error-name-mixedcase */
    error PAUSED();
    error NOT_PAUSED();
    error LOCKED_NO_REENTER();
    error INVALID_PROVIDER();
    error THIRD_PARTY_CONTRACTS_FLAG_NOT_SET();
    error INSUFFICIENT_DEPOSIT();
    error INVALID_ASSET_ID();
    error INVALID_ASSET_ADDRESS();
    error INVALID_LINKED_TOKEN_ADDRESS();
    error INVALID_LINKED_BRIDGE_ADDRESS();
    error INVALID_BRIDGE_ID(); // TODO: replace with INVALID_BRIDGE_CALL_DATA() once rollup processor is redeployed
    error INVALID_BRIDGE_ADDRESS();
    error BRIDGE_ID_IS_INCONSISTENT(); // TODO: replace with INCONSISTENT_BRIDGE_CALL_DATA()
    error BRIDGE_WITH_IDENTICAL_INPUT_ASSETS(uint256 inputAssetId);
    error BRIDGE_WITH_IDENTICAL_OUTPUT_ASSETS(uint256 outputAssetId);
    error ZERO_TOTAL_INPUT_VALUE();
    error ARRAY_OVERFLOW();
    error MSG_VALUE_WRONG_AMOUNT();
    error INSUFFICIENT_ETH_PAYMENT();
    error WITHDRAW_TO_ZERO_ADDRESS();
    error DEPOSIT_TOKENS_WRONG_PAYMENT_TYPE();
    error INSUFFICIENT_TOKEN_APPROVAL();
    error NONZERO_OUTPUT_VALUE_ON_NOT_USED_ASSET(uint256 outputValue);
    error INCORRECT_STATE_HASH(bytes32 oldStateHash, bytes32 newStateHash);
    error INCORRECT_DATA_START_INDEX(uint256 providedIndex, uint256 expectedIndex);
    error INCORRECT_PREVIOUS_DEFI_INTERACTION_HASH(
        bytes32 providedDefiInteractionHash,
        bytes32 expectedDefiInteractionHash
    );
    error PUBLIC_INPUTS_HASH_VERIFICATION_FAILED(uint256, uint256);
    error PROOF_VERIFICATION_FAILED();
    error ASYNC_NONZERO_OUTPUT_VALUES(uint256 outputValueA, uint256 outputValueB);
    error OUTPUT_A_EXCEEDS_252_BITS(uint256 outputValueA);
    error OUTPUT_B_EXCEEDS_252_BITS(uint256 outputValueb);
    /* solhint-enable error-name-mixedcase */
    error UnsupportedAsset(address);

    // error lib errors
    error InvalidCaller();
    error InputAssetAAndOutputAssetAIsEth();
    error InputAssetANotERC20OrEth();
    error OutputAssetANotERC20OrEth();
    error InputAssetBNotEmpty();
    error OutputAssetBNotEmpty();
    error InputAssetInvalid();
    error OutputAssetInvalid();
    error InputAssetNotEqZkAToken();
    error InvalidAToken();
    error ZkTokenAlreadyExists();
    error ZkTokenDontExist();
    error ZeroValue();
    error AsyncDisabled();

    event OffchainData(uint256 indexed rollupId, uint256 chunk, uint256 totalChunks, address sender);
    event RollupProcessed(uint256 indexed rollupId, bytes32[] nextExpectedDefiHashes, address sender);
    event DefiBridgeProcessed(
        uint256 indexed bridgeCallData,
        uint256 indexed nonce,
        uint256 totalInputValue,
        uint256 totalOutputValueA,
        uint256 totalOutputValueB,
        bool result,
        bytes errorReason
    );
    event AsyncDefiBridgeProcessed(uint256 indexed bridgeCallData, uint256 indexed nonce, uint256 totalInputValue);
    event Deposit(uint256 indexed assetId, address indexed depositorAddress, uint256 depositValue);
    event WithdrawError(bytes errorReason);
    event AssetAdded(uint256 indexed assetId, address indexed assetAddress, uint256 assetGasLimit);
    event BridgeAdded(uint256 indexed bridgeAddressId, address indexed bridgeAddress, uint256 bridgeGasLimit);
    event RollupProviderUpdated(address indexed providerAddress, bool valid);
    event VerifierUpdated(address indexed verifierAddress);
    event Paused(address account);
    event Unpaused(address account);

    uint256 private constant INPUT_ASSET_ID_A_SHIFT = 32;
    uint256 private constant INPUT_ASSET_ID_B_SHIFT = 62;
    uint256 private constant OUTPUT_ASSET_ID_A_SHIFT = 92;
    uint256 private constant OUTPUT_ASSET_ID_B_SHIFT = 122;
    uint256 private constant BITCONFIG_SHIFT = 152;
    uint256 private constant AUX_DATA_SHIFT = 184;
    uint256 private constant VIRTUAL_ASSET_ID_FLAG_SHIFT = 29;
    uint256 private constant VIRTUAL_ASSET_ID_FLAG = 0x20000000; // 2 ** 29
    uint256 private constant MASK_THIRTY_TWO_BITS = 0xffffffff;
    uint256 private constant MASK_THIRTY_BITS = 0x3fffffff;
    uint256 private constant MASK_SIXTY_FOUR_BITS = 0xffffffffffffffff;
    // offset we add to `proofData` to point to rollupBeneficiary
    uint256 internal constant ROLLUP_BENEFICIARY_OFFSET = 4512; // ROLLUP_HEADER_LENGTH - 0x20

    IRollupProcessor internal constant ROLLUP_PROCESSOR = IRollupProcessor(0xFF1F2B4ADb9dF6FC8eAFecDcbF96A2B351680455);
    IRollupProcessor internal constant IMPLEMENTATION = IRollupProcessor(0x3f972e325CecD99a6be267fd36ceB46DCa7C3F28);

    ISubsidy internal constant SUBSIDY = ISubsidy(0xABc30E831B5Cc173A9Ed5941714A7845c909e7fA);

    address internal constant ROLLUP_PROVIDER = payable(0xA173BDdF4953C1E8be2cA0695CFc07502Ff3B1e7);
    address internal constant MULTI_SIG = 0xE298a76986336686CC3566469e3520d23D1a8aaD;

    bytes32 public constant BRIDGE_PROCESSED_EVENT_SIG =
        keccak256("DefiBridgeProcessed(uint256,uint256,uint256,uint256,uint256,bool,bytes)");
    bytes32 public constant ASYNC_BRIDGE_PROCESSED_EVENT_SIG =
        keccak256("AsyncDefiBridgeProcessed(uint256,uint256,uint256)");

    AztecTypes.AztecAsset internal emptyAsset;

    uint256 public nextRollupId = 0;
    address public rollupBeneficiary;

    constructor() {
        vm.label(address(ROLLUP_PROCESSOR), "Rollup");
        vm.label(address(IMPLEMENTATION), "Implementation");
        vm.label(address(SUBSIDY), "Subsidy");
        vm.label(ROLLUP_PROVIDER, "Rollup Provider");
        vm.label(MULTI_SIG, "Multisig");
        vm.label(ROLLUP_PROCESSOR.verifier(), "Verifier");
        vm.label(ROLLUP_PROCESSOR.defiBridgeProxy(), "DefiBridgeProxy");
    }

    /**
     * @notice Helper function to fetch nonce for the next interaction
     * @return The nonce of the next defi interaction
     */
    function getNextNonce() public view returns (uint256) {
        return nextRollupId * 32;
    }

    /**
     * @notice Helper function to get an `AztecAsset` object for the supported `_asset`
     * @dev if `_asset` is not supported will revert with `UnsupportedAsset(_asset)`.
     * @param _asset The address of the asset to fetch
     * @return A populated supported `AztecAsset`
     */
    function getRealAztecAsset(address _asset) public view returns (AztecTypes.AztecAsset memory) {
        if (_asset == address(0)) {
            return AztecTypes.AztecAsset({id: 0, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.ETH});
        } else {
            return
                AztecTypes.AztecAsset({
                    id: tokenToId(_asset),
                    erc20Address: _asset,
                    assetType: AztecTypes.AztecAssetType.ERC20
                });
        }
    }

    /**
     * @notice Helper function to get the id a given `_asset`
     * @dev if `_asset` is not supported will revert with `UnsupportedAsset(_asset)`
     * @param _asset The address of the asset to fetch id for
     * @return The id matching `_asset`
     */
    function tokenToId(address _asset) public view returns (uint256) {
        if (_asset == address(0)) {
            return 0;
        }
        uint256 length = ROLLUP_PROCESSOR.getSupportedAssetsLength();
        for (uint256 i = 1; i <= length; i++) {
            address fetched = ROLLUP_PROCESSOR.getSupportedAsset(i);
            if (fetched == _asset) {
                return i;
            }
        }
        revert UnsupportedAsset(_asset);
    }

    /**
     * @notice Helper function to check if `_asset` is supported or not
     * @param _asset The address of the asset
     * @return True if the asset is supported, false otherwise
     */
    function isSupportedAsset(address _asset) public view returns (bool) {
        if (_asset == address(0)) {
            return true;
        }
        uint256 length = ROLLUP_PROCESSOR.getSupportedAssetsLength();
        for (uint256 i = 1; i <= length; i++) {
            address fetched = ROLLUP_PROCESSOR.getSupportedAsset(i);
            if (fetched == _asset) {
                return true;
            }
        }
        return false;
    }

    /**
     * @notice Helper function to encode bridge call data into a bit-string
     * @dev For more info see the rollup implementation at "rollup.aztec.eth" that decodes
     * @param _bridgeAddressId id of the specific bridge (index in supportedBridge + 1)
     * @param _inputAssetA The first input asset
     * @param _inputAssetB The second input asset
     * @param _outputAssetA The first output asset
     * @param _outputAssetB The second output asset
     * @param _auxData Auxiliary data that is passed to the bridge
     * @return encodedBridgeCallData - The encoded bitmap containing encoded information about the call
     */
    function encodeBridgeCallData(
        uint256 _bridgeAddressId,
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory _inputAssetB,
        AztecTypes.AztecAsset memory _outputAssetA,
        AztecTypes.AztecAsset memory _outputAssetB,
        uint256 _auxData
    ) public pure returns (uint256 encodedBridgeCallData) {
        encodedBridgeCallData = _bridgeAddressId & MASK_THIRTY_TWO_BITS;

        // Input assets
        encodedBridgeCallData = encodedBridgeCallData | (_encodeAsset(_inputAssetA) << INPUT_ASSET_ID_A_SHIFT);
        encodedBridgeCallData = encodedBridgeCallData | (_encodeAsset(_inputAssetB) << INPUT_ASSET_ID_B_SHIFT);
        encodedBridgeCallData = encodedBridgeCallData | (_encodeAsset(_outputAssetA) << OUTPUT_ASSET_ID_A_SHIFT);
        encodedBridgeCallData = encodedBridgeCallData | (_encodeAsset(_outputAssetB) << OUTPUT_ASSET_ID_B_SHIFT);

        // Aux data
        encodedBridgeCallData = encodedBridgeCallData | ((_auxData & MASK_SIXTY_FOUR_BITS) << AUX_DATA_SHIFT);

        // bitconfig
        uint256 bitConfig = (_inputAssetB.assetType != AztecTypes.AztecAssetType.NOT_USED ? 1 : 0) |
            (_outputAssetB.assetType != AztecTypes.AztecAssetType.NOT_USED ? 2 : 0);
        encodedBridgeCallData = encodedBridgeCallData | (bitConfig << BITCONFIG_SHIFT);
    }

    /**
     * @notice Helper function for processing a rollup with a specific call data and `_totalInputValue`
     * @dev will impersonate the rollup processor and update rollup state
     * @param _encodedBridgeCallData The encoded bridge call data for the action, e.g., output from `encodeBridgeCallData()`
     * @param _totalInputValue The value of inputAssetA and inputAssetB to transfer to the bridge
     * @return outputValueA The amount of outputAssetA returned from the DeFi bridge interaction in this rollup
     * @return outputValueB The amount of outputAssetB returned from the DeFi bridge interaction in this rollup
     * @return isAsync A flag indicating whether the DeFi bridge interaction in this rollup was async
     */
    function sendDefiRollup(uint256 _encodedBridgeCallData, uint256 _totalInputValue)
        public
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        )
    {
        _prepareRollup();
        bytes memory proofData = _getProofData(_encodedBridgeCallData, _totalInputValue);

        vm.recordLogs();
        vm.prank(ROLLUP_PROVIDER);
        ROLLUP_PROCESSOR.processRollup(proofData, "");
        nextRollupId++;

        return _getDefiBridgeProcessedData();
    }

    /**
     * @notice Sets `rollupBeneficiary` storage variable
     * @param _rollupBeneficiary An address which receives rollup block's fee
     */
    function setRollupBeneficiary(address _rollupBeneficiary) public {
        rollupBeneficiary = _rollupBeneficiary;
    }

    /**
     * @notice A function which iterates through logs, decodes relevant events and returns values which were originally
     *         returned from bridge's `convert(...)` function.
     * @dev You have to call `vm.recordLogs()` before calling this function
     * @dev If there are multiple DefiBridgeProcessed events, values of the last one are returned --> this occurs when
     *      the bridge finalises interactions within it's convert functions. Returning values of the last ones works
     *      because the last emitted DefiBridgeProcessed event corresponds to the `convert(...)` call.
     * @return outputValueA the amount of outputAssetA returned from the DeFi bridge interaction in this rollup
     * @return outputValueB the amount of outputAssetB returned from the DeFi bridge interaction in this rollup
     * @return isAsync a flag indicating whether the DeFi bridge interaction in this rollup was async
     */
    function _getDefiBridgeProcessedData()
        internal
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        )
    {
        Vm.Log[] memory logs = vm.getRecordedLogs();

        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] == BRIDGE_PROCESSED_EVENT_SIG) {
                (, outputValueA, outputValueB) = abi.decode(logs[i].data, (uint256, uint256, uint256));
            } else if (logs[i].topics[0] == ASYNC_BRIDGE_PROCESSED_EVENT_SIG) {
                // We don't return totalInputValue so there is no need to decode the event's data
                return (0, 0, true);
            }
        }
    }

    /**
     * @notice Helper function that will overwrite the rollup state to let us mock the rollup proof
     * @dev Resets the rollupState to the initial state
     * @dev if first run, also resets the data size and start index of the rollup
     * @dev Mock any verifier call to return true to let builder focus on contract side of things
     */
    function _prepareRollup() internal {
        // Overwrite the rollup state hash
        {
            bytes32 rollupStateHash = keccak256(
                abi.encode(
                    uint256(nextRollupId),
                    0x18ceb5cd201e1cee669a5c3ad96d3c4e933a365b37046fc3178264bede32c68d,
                    0x298329c7d0936453f354e4a5eef4897296cc0bf5a66f2a528318508d2088dafa,
                    0x2fd2364bfe47ccb410eba3a958be9f39a8c6aca07db1abd15f5a211f51505071,
                    0x2e4ab7889ab3139204945f9e722c7a8fdb84e66439d787bd066c3d896dba04ea
                )
            );
            vm.store(address(ROLLUP_PROCESSOR), bytes32(uint256(9)), rollupStateHash);
        }

        if (nextRollupId == 0) {
            // Overwrite the start index and data size. Resets rollup state.
            vm.store(
                address(ROLLUP_PROCESSOR),
                bytes32(uint256(2)),
                bytes32(uint256(uint160(ROLLUP_PROCESSOR.verifier())))
            );
        }

        // Overwrite the previous defi interaction hash
        vm.store(
            address(ROLLUP_PROCESSOR),
            bytes32(uint256(16)),
            0x14e0f351ade4ba10438e9b15f66ab2e6389eea5ae870d6e8b2df1418b2e6fd5b
        );

        vm.mockCall(ROLLUP_PROCESSOR.verifier(), "", abi.encode(true));
    }

    function _encodeAsset(AztecTypes.AztecAsset memory _asset) internal pure returns (uint256) {
        if (_asset.assetType == AztecTypes.AztecAssetType.VIRTUAL) {
            return (_asset.id & MASK_THIRTY_BITS) | VIRTUAL_ASSET_ID_FLAG;
        }
        return _asset.id & MASK_THIRTY_BITS;
    }

    /**
     * @notice Helper function to generate a mock rollup proof that calls a specific bridge with `_totalInputValue`
     * @param _encodedBridgeCallData The encoded call, e.g., output from `encodeBridgeCallData()`
     * @param _totalInputValue The amount of inputAssetA and inputAssetB to transfer to the defi bridge.
     * @return data Encoded mock proof data.
     */
    function _getProofData(uint256 _encodedBridgeCallData, uint256 _totalInputValue)
        internal
        view
        returns (bytes memory data)
    {
        uint256 nextRollupId_ = nextRollupId;

        /* solhint-disable no-inline-assembly */
        assembly {
            data := mload(0x40)
            let length := 0x12c0
            mstore(0x40, add(add(data, length), 0x20))

            mstore(data, length)
            mstore(add(data, 0x20), nextRollupId_)
            mstore(add(data, 0x60), mul(nextRollupId_, 2))
            mstore(add(data, 0x180), _encodedBridgeCallData)
            mstore(add(data, 0x580), _totalInputValue)
            mstore(add(data, 0x11a0), sload(rollupBeneficiary.slot))

            // Mock values
            // mstore(add(data, 0x20), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x40), 0x0000000000000000000000000000000000000000000000000000000000000001)
            //mstore(add(data, 0x60), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x80), 0x18ceb5cd201e1cee669a5c3ad96d3c4e933a365b37046fc3178264bede32c68d)
            mstore(add(data, 0xa0), 0x18ceb5cd201e1cee669a5c3ad96d3c4e933a365b37046fc3178264bede32c68d)
            mstore(add(data, 0xc0), 0x298329c7d0936453f354e4a5eef4897296cc0bf5a66f2a528318508d2088dafa)
            mstore(add(data, 0xe0), 0x298329c7d0936453f354e4a5eef4897296cc0bf5a66f2a528318508d2088dafa)
            mstore(add(data, 0x100), 0x2fd2364bfe47ccb410eba3a958be9f39a8c6aca07db1abd15f5a211f51505071)
            mstore(add(data, 0x120), 0x2fd2364bfe47ccb410eba3a958be9f39a8c6aca07db1abd15f5a211f51505071)
            mstore(add(data, 0x140), 0x2e4ab7889ab3139204945f9e722c7a8fdb84e66439d787bd066c3d896dba04ea)
            mstore(add(data, 0x160), 0x2e4ab7889ab3139204945f9e722c7a8fdb84e66439d787bd066c3d896dba04ea)
            // mstore(add(data, 0x180), 0x0000000000000000000000000000000000000000000000000000000100000002)
            mstore(add(data, 0x1a0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x1c0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x1e0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x200), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x220), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x240), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x260), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x280), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x2a0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x2c0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x2e0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x300), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x320), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x340), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x360), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x380), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x3a0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x3c0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x3e0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x400), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x420), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x440), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x460), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x480), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x4a0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x4c0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x4e0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x500), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x520), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x540), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x560), 0x0000000000000000000000000000000000000000000000000000000000000000)
            // mstore(add(data, 0x580), 0x0000000000000000000000000000000000000000000000000000000000000014)
            mstore(add(data, 0x5a0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x5c0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x5e0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x600), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x620), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x640), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x660), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x680), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x6a0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x6c0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x6e0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x700), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x720), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x740), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x760), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x780), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x7a0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x7c0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x7e0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x800), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x820), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x840), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x860), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x880), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x8a0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x8c0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x8e0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x900), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x920), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x940), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x960), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x980), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x9a0), 0x0000000000000000000000000000000000000000000000000000000040000000)
            mstore(add(data, 0x9c0), 0x0000000000000000000000000000000000000000000000000000000040000000)
            mstore(add(data, 0x9e0), 0x0000000000000000000000000000000000000000000000000000000040000000)
            mstore(add(data, 0xa00), 0x0000000000000000000000000000000000000000000000000000000040000000)
            mstore(add(data, 0xa20), 0x0000000000000000000000000000000000000000000000000000000040000000)
            mstore(add(data, 0xa40), 0x0000000000000000000000000000000000000000000000000000000040000000)
            mstore(add(data, 0xa60), 0x0000000000000000000000000000000000000000000000000000000040000000)
            mstore(add(data, 0xa80), 0x0000000000000000000000000000000000000000000000000000000040000000)
            mstore(add(data, 0xaa0), 0x0000000000000000000000000000000000000000000000000000000040000000)
            mstore(add(data, 0xac0), 0x0000000000000000000000000000000000000000000000000000000040000000)
            mstore(add(data, 0xae0), 0x0000000000000000000000000000000000000000000000000000000040000000)
            mstore(add(data, 0xb00), 0x0000000000000000000000000000000000000000000000000000000040000000)
            mstore(add(data, 0xb20), 0x0000000000000000000000000000000000000000000000000000000040000000)
            mstore(add(data, 0xb40), 0x0000000000000000000000000000000000000000000000000000000040000000)
            mstore(add(data, 0xb60), 0x0000000000000000000000000000000000000000000000000000000040000000)
            mstore(add(data, 0xb80), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xba0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xbc0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xbe0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xc00), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xc20), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xc40), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xc60), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xc80), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xca0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xcc0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xce0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xd00), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xd20), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xd40), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xd60), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xd80), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xda0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xdc0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xde0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xe00), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xe20), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xe40), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xe60), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xe80), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xea0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xec0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xee0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xf00), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xf20), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xf40), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xf60), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xf80), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xfa0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xfc0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0xfe0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x1000), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x1020), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x1040), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x1060), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x1080), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x10a0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x10c0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x10e0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x1100), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x1120), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x1140), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x1160), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x1180), 0x14e0f351ade4ba10438e9b15f66ab2e6389eea5ae870d6e8b2df1418b2e6fd5b)
            // mstore(add(data, 0x11a0), 0x000000000000000000000000ddb3b44eaf58792a5a8dded7da7561a671138b80)
            mstore(add(data, 0x11c0), 0x0000000000000000000000000000000000000000000000000000000000000001)
            mstore(add(data, 0x11e0), 0x0000000000000000000000000000000000000000000000000000000000000003)
            mstore(add(data, 0x1200), 0xc7336c7aeff11bdfcb8203789aea9cfbaf54d9a60a590d3dbc3bac681126be84)
            mstore(add(data, 0x1220), 0xbf057586ee1142613502b8a6476690f8ed27f0acee5bf4d7a3bb763d86ff092a)
            mstore(add(data, 0x1240), 0x0000000000000000000000000000000056fe413cadb2e67b0b3656d623451b3b)
            mstore(add(data, 0x1260), 0x00000000000000000000000000000000aa89cf7553765b24c54589bbcedfc4ef)
            mstore(add(data, 0x1280), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x12a0), 0x0000000000000000000000000000000000000000000000000000000000000000)
            mstore(add(data, 0x12c0), 0x0000000000000000000000000000000000000000000000000000000000000000)
        }
        /* solhint-enable no-inline-assembly */
    }
}
