// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

interface IRollupProcessor {
    function defiBridgeProxy() external view returns (address);

    function processRollup(
        bytes calldata proofData,
        bytes calldata signatures,
        bytes calldata offchainTxData
    ) external;

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
        address spender,
        uint256 permitApprovalAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    function receiveEthFromBridge(uint256 interactionNonce) external payable;

    function setRollupProvider(address provderAddress, bool valid) external;

    function approveProof(bytes32 _proofHash) external;

    function pause() external;

    function setDefiBridgeProxy(address feeDistributorAddress) external;

    function setVerifier(address verifierAddress) external;

    function setSupportedAsset(
        address linkedToken,
        bool supportsPermit,
        uint256 gasLimit
    ) external;

    function setAssetPermitSupport(uint256 assetId, bool supportsPermit) external;

    function setSupportedBridge(address linkedBridge, uint256 gasLimit) external;

    function getSupportedAsset(uint256 assetId) external view returns (address);

    function getSupportedAssets() external view returns (address[] memory);

    function getSupportedBridge(uint256 bridgeAddressId) external view returns (address);

    function getBridgeGasLimit(uint256 bridgeAddressId) external view returns (uint256);

    function getSupportedBridges() external view returns (address[] memory);

    function getAssetPermitSupport(uint256 assetId) external view returns (bool);

    function getEscapeHatchStatus() external view returns (bool, uint256);

    function getUserPendingDeposit(uint256 assetId, address userAddress) external view returns (uint256);

    function processAsyncDefiInteraction(uint256 interactionNonce) external returns (bool);

    function getDefiInteractionBlockNumber(uint256 interactionNonce) external view returns (uint256);

    event DefiBridgeProcessed(
        uint256 indexed bridgeId,
        uint256 indexed nonce,
        uint256 totalInputValue,
        uint256 totalOutputValueA,
        uint256 totalOutputValueB,
        bool result
    );
    event AsyncDefiBridgeProcessed(
        uint256 indexed bridgeId,
        uint256 indexed nonce,
        uint256 totalInputValue,
        uint256 totalOutputValueA,
        uint256 totalOutputValueB,
        bool result
    );
}
