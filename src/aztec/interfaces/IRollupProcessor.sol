// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
pragma solidity >=0.8.4;

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

    function setRollupProvider(address providerAddress, bool valid) external;

    function setVerifier(address verifierAddress) external;

    function setAllowThirdPartyContracts(bool _flag) external;

    function setDefiBridgeProxy(address feeDistributorAddress) external;

    function setSupportedAsset(address linkedToken, uint256 gasLimit) external;

    function setSupportedBridge(address linkedBridge, uint256 gasLimit) external;

    function processRollup(bytes calldata proofData, bytes calldata signatures) external;

    function receiveEthFromBridge(uint256 interactionNonce) external payable;

    function approveProof(bytes32 _proofHash) external;

    function depositPendingFunds(
        uint256 assetId,
        uint256 amount,
        address owner,
        bytes32 proofHash
    ) external payable;

    function depositPendingFundsPermit(
        uint256 assetId,
        uint256 amount,
        address owner,
        bytes32 proofHash,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function depositPendingFundsPermitNonStandard(
        uint256 assetId,
        uint256 amount,
        address owner,
        bytes32 proofHash,
        uint256 nonce,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function offchainData(
        uint256 rollupId,
        uint256 chunk,
        uint256 totalChunks,
        bytes calldata offchainTxData
    ) external;

    function processAsyncDefiInteraction(uint256 interactionNonce) external returns (bool);

    /*----------------------------------------
      NON-MUTATING FUNCTIONS
      ----------------------------------------*/

    function rollupStateHash() external view returns (bytes32);

    function userPendingDeposits(uint256 assetId, address userAddress) external view returns (uint256);

    function defiBridgeProxy() external view returns (address);

    function prevDefiInteractionsHash() external view returns (bytes32);

    function paused() external view returns (bool);

    function verifier() external view returns (address);

    function getDataSize() external view returns (uint256);

    function getPendingDefiInteractionHashesLength() external view returns (uint256);

    function getDefiInteractionHashesLength() external view returns (uint256);

    function getAsyncDefiInteractionHashesLength() external view returns (uint256 res);

    function getSupportedBridge(uint256 bridgeAddressId) external view returns (address);

    function getSupportedBridgesLength() external view returns (uint256);

    function getSupportedAssetsLength() external view returns (uint256);

    function getSupportedAsset(uint256 assetId) external view returns (address);

    function getBridgeGasLimit(uint256 bridgeAddressId) external view returns (uint256);

    function getEscapeHatchStatus() external view returns (bool, uint256);

    function getDefiInteractionHashes() external view returns (bytes32[] memory);

    function getAsyncDefiInteractionHashes() external view returns (bytes32[] memory);

    function getSupportedAssets() external view returns (address[] memory, uint256[] memory);

    function getSupportedBridges() external view returns (address[] memory, uint256[] memory);
}
