// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
pragma solidity >=0.8.4;

// @dev For documentation of the functions within this interface see RollupProcessor contract
interface IRollupProcessor {
    /*----------------------------------------
    EVENTS
    ----------------------------------------*/
    event OffchainData(uint256 indexed rollupId, uint256 chunk, uint256 totalChunks, address sender);
    event RollupProcessed(uint256 indexed rollupId, bytes32[] nextExpectedDefiHashes, address sender);
    event DefiBridgeProcessed(
        uint256 indexed encodedBridgeCallData,
        uint256 indexed nonce,
        uint256 totalInputValue,
        uint256 totalOutputValueA,
        uint256 totalOutputValueB,
        bool result,
        bytes errorReason
    );
    event AsyncDefiBridgeProcessed(
        uint256 indexed encodedBridgeCallData,
        uint256 indexed nonce,
        uint256 totalInputValue
    );
    event Deposit(uint256 indexed assetId, address indexed depositorAddress, uint256 depositValue);
    event WithdrawError(bytes errorReason);
    event AssetAdded(uint256 indexed assetId, address indexed assetAddress, uint256 assetGasLimit);
    event BridgeAdded(uint256 indexed bridgeAddressId, address indexed bridgeAddress, uint256 bridgeGasLimit);
    event RollupProviderUpdated(address indexed providerAddress, bool valid);
    event VerifierUpdated(address indexed verifierAddress);
    event Paused(address account);
    event Unpaused(address account);

    /*----------------------------------------
      MUTATING FUNCTIONS
      ----------------------------------------*/

    function pause() external;

    function unpause() external;

    function setRollupProvider(address _provider, bool _valid) external;

    function setVerifier(address _verifier) external;

    function setAllowThirdPartyContracts(bool _allowThirdPartyContracts) external;

    function setDefiBridgeProxy(address _defiBridgeProxy) external;

    function setSupportedAsset(address _token, uint256 _gasLimit) external;

    function setSupportedBridge(address _bridge, uint256 _gasLimit) external;

    function processRollup(bytes calldata _encodedProofData, bytes calldata _signatures) external;

    function receiveEthFromBridge(uint256 _interactionNonce) external payable;

    function approveProof(bytes32 _proofHash) external;

    function depositPendingFunds(
        uint256 _assetId,
        uint256 _amount,
        address _owner,
        bytes32 _proofHash
    ) external payable;

    function offchainData(
        uint256 _rollupId,
        uint256 _chunk,
        uint256 _totalChunks,
        bytes calldata _offchainTxData
    ) external;

    function processAsyncDefiInteraction(uint256 _interactionNonce) external returns (bool);

    /*----------------------------------------
      NON-MUTATING FUNCTIONS
      ----------------------------------------*/

    function rollupStateHash() external view returns (bytes32);

    function userPendingDeposits(uint256 _assetId, address _user) external view returns (uint256);

    function defiBridgeProxy() external view returns (address);

    function prevDefiInteractionsHash() external view returns (bytes32);

    function paused() external view returns (bool);

    function verifier() external view returns (address);

    function getDataSize() external view returns (uint256);

    function getPendingDefiInteractionHashesLength() external view returns (uint256);

    function getDefiInteractionHashesLength() external view returns (uint256);

    function getAsyncDefiInteractionHashesLength() external view returns (uint256);

    function getSupportedBridge(uint256 _bridgeAddressId) external view returns (address);

    function getSupportedBridgesLength() external view returns (uint256);

    function getSupportedAssetsLength() external view returns (uint256);

    function getSupportedAsset(uint256 _assetId) external view returns (address);

    function getEscapeHatchStatus() external view returns (bool, uint256);

    function assetGasLimits(uint256 _bridgeAddressId) external view returns (uint256);

    function bridgeGasLimits(uint256 _bridgeAddressId) external view returns (uint256);
}
