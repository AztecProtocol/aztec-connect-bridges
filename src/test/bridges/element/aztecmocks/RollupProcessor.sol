// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
pragma solidity >=0.8.4;

import {IDefiBridge} from "../../../../aztec/interfaces/IDefiBridge.sol";
import {DefiBridgeProxy} from "./DefiBridgeProxy.sol";
import {AztecTypes} from "../../../../aztec/libraries/AztecTypes.sol";
import {TokenTransfers} from "./libraries/TokenTransfers.sol";

/**
 * @notice Mock rollup processor to be used in testing. Will revert on a failing bridge to make debugging easier
 */
contract RollupProcessor {
    error INSUFFICIENT_ETH_PAYMENT();

    event DefiBridgeProcessed(
        uint256 indexed bridgeCallData,
        uint256 indexed nonce,
        uint256 totalInputValue,
        uint256 totalOutputValueA,
        uint256 totalOutputValueB,
        bool result
    );

    event AsyncDefiBridgeProcessed(uint256 indexed bridgeCallData, uint256 indexed nonce, uint256 totalInputValue);

    struct DefiInteraction {
        address bridgeAddress;
        AztecTypes.AztecAsset inputAssetA;
        AztecTypes.AztecAsset inputAssetB;
        AztecTypes.AztecAsset outputAssetA;
        AztecTypes.AztecAsset outputAssetB;
        uint256 totalInputValue;
        uint256 interactionNonce;
        uint256 auxInputData; // (auxData)
        uint256 outputValueA;
        uint256 outputValueB;
        bool finalised;
    }

    // DEFI_BRIDGE_PROXY_CONVERT_SELECTOR = function signature of:
    //   function convert(
    //       address,
    //       AztecTypes.AztecAsset memory inputAssetA,
    //       AztecTypes.AztecAsset memory inputAssetB,
    //       AztecTypes.AztecAsset memory outputAssetA,
    //       AztecTypes.AztecAsset memory outputAssetB,
    //       uint256 totalInputValue,
    //       uint256 interactionNonce,
    //       uint256 auxData,
    //       uint256 ethPaymentsSlot
    //       address rollupBeneficary)
    // N.B. this is the selector of the 'convert' function of the DefiBridgeProxy contract.
    //      This has a different interface to the IDefiBridge.convert function
    bytes4 private constant DEFI_BRIDGE_PROXY_CONVERT_SELECTOR = 0x4bd947a8;

    DefiBridgeProxy private bridgeProxy;

    uint256 private constant NUMBER_OF_BRIDGE_CALLS = 32;
    mapping(uint256 => uint256) ethPayments;
    mapping(address => uint256) bridgeGasLimits;

    function receiveEthFromBridge(uint256 interactionNonce) external payable {
        ethPayments[interactionNonce] += msg.value;
    }

    function setBridgeGasLimit(address bridgeAddress, uint256 gasLimit) external {
        bridgeGasLimits[bridgeAddress] = gasLimit;
    }

    function getBridgeGasLimit(address bridgeAddress) private view returns (uint256 limit) {
        limit = bridgeGasLimits[bridgeAddress];
        limit = limit == 0 ? 200000 : limit;
    }

    function getDefiResult(uint256 nonce) public returns (bool finalised, uint256 outputValueA) {
        finalised = defiInteractions[nonce].finalised;
        outputValueA = defiInteractions[nonce].outputValueA;
    }

    mapping(uint256 => DefiInteraction) public defiInteractions;

    constructor(address _bridgeProxyAddress) {
        bridgeProxy = DefiBridgeProxy(_bridgeProxyAddress);
    }

    /**
     * @dev Token transfer method used by processAsyncDefiInteraction
     * Calls `transferFrom` on the target erc20 token, if asset is of type ERC
     * If asset is ETH, we validate a payment has been made against the provided interaction nonce
     * @param bridgeContract address of bridge contract we're taking tokens from
     * @param asset the AztecAsset being transferred
     * @param outputValue the expected value transferred
     * @param interactionNonce the defi interaction nonce of the interaction
     */
    function transferTokensAsync(
        address bridgeContract,
        AztecTypes.AztecAsset memory asset,
        uint256 outputValue,
        uint256 interactionNonce
    ) internal {
        if (outputValue == 0) {
            return;
        }
        if (asset.assetType == AztecTypes.AztecAssetType.ETH) {
            if (outputValue > ethPayments[interactionNonce]) {
                revert INSUFFICIENT_ETH_PAYMENT();
            }
            ethPayments[interactionNonce] = 0;
        } else if (asset.assetType == AztecTypes.AztecAssetType.ERC20) {
            address tokenAddress = asset.erc20Address;
            TokenTransfers.safeTransferFrom(tokenAddress, bridgeContract, address(this), outputValue);
        }
    }

    function processAsyncDefiInteraction(uint256 interactionNonce) external returns (bool completed) {
        // call canFinalise on the bridge
        // call finalise on the bridge
        DefiInteraction storage interaction = defiInteractions[interactionNonce];
        require(interaction.bridgeAddress != address(0), "Rollup Contract: UNKNOWN_NONCE");

        (uint256 outputValueA, uint256 outputValueB, bool interactionComplete) = IDefiBridge(interaction.bridgeAddress)
            .finalise(
                interaction.inputAssetA,
                interaction.inputAssetB,
                interaction.outputAssetA,
                interaction.outputAssetB,
                interaction.interactionNonce,
                uint64(interaction.auxInputData)
            );
        completed = interactionComplete;

        if (outputValueB > 0 && interaction.outputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED) {
            require(false, "Non-zero output value on non-existant asset!");
        }
        if (outputValueA == 0 && outputValueB == 0) {
            // issue refund.
            transferTokensAsync(
                address(interaction.bridgeAddress),
                interaction.inputAssetA,
                interaction.totalInputValue,
                interaction.interactionNonce
            );
        } else {
            // transfer output tokens to rollup contract
            transferTokensAsync(
                address(interaction.bridgeAddress),
                interaction.outputAssetA,
                outputValueA,
                interaction.interactionNonce
            );
            transferTokensAsync(
                address(interaction.bridgeAddress),
                interaction.outputAssetB,
                outputValueB,
                interaction.interactionNonce
            );
        }

        emit DefiBridgeProcessed(
            0,
            interaction.interactionNonce,
            interaction.totalInputValue,
            outputValueA,
            outputValueB,
            true
        );
        interaction.finalised = true;
        interaction.outputValueA = outputValueA;
        interaction.outputValueB = outputValueB;
    }

    struct ConvertArgs {
        address bridgeAddress;
        AztecTypes.AztecAsset inputAssetA;
        AztecTypes.AztecAsset inputAssetB;
        AztecTypes.AztecAsset outputAssetA;
        AztecTypes.AztecAsset outputAssetB;
        uint256 totalInputValue;
        uint256 interactionNonce;
        uint256 auxInputData;
        uint256 ethPaymentsSlot;
    }

    struct ConvertReturnValues {
        uint256 outputValueA;
        uint256 outputValueB;
        bool isAsync;
    }

    function _convert(ConvertArgs memory convertArgs) private returns (ConvertReturnValues memory results) {
        defiInteractions[convertArgs.interactionNonce] = DefiInteraction(
            convertArgs.bridgeAddress,
            convertArgs.inputAssetA,
            convertArgs.inputAssetB,
            convertArgs.outputAssetA,
            convertArgs.outputAssetB,
            convertArgs.totalInputValue,
            convertArgs.interactionNonce,
            convertArgs.auxInputData,
            0,
            0,
            false
        );
        uint256 gas = bridgeGasLimits[convertArgs.bridgeAddress] > 0
            ? bridgeGasLimits[convertArgs.bridgeAddress]
            : uint256(150000000);

        (bool success, bytes memory result) = address(bridgeProxy).delegatecall{gas: gas}(
            abi.encodeWithSelector(
                DEFI_BRIDGE_PROXY_CONVERT_SELECTOR,
                convertArgs.bridgeAddress,
                convertArgs.inputAssetA,
                convertArgs.inputAssetB,
                convertArgs.outputAssetA,
                convertArgs.outputAssetB,
                convertArgs.totalInputValue,
                convertArgs.interactionNonce,
                convertArgs.auxInputData,
                convertArgs.ethPaymentsSlot,
                address(0)
            )
        );
        results = ConvertReturnValues(0, 0, false);

        if (success) {
            (uint256 outputValueA, uint256 outputValueB, bool isAsync) = abi.decode(result, (uint256, uint256, bool));
            if (!isAsync) {
                emit DefiBridgeProcessed(
                    0,
                    convertArgs.interactionNonce,
                    convertArgs.totalInputValue,
                    outputValueA,
                    outputValueB,
                    true
                );
            } else {
                emit AsyncDefiBridgeProcessed(0, convertArgs.interactionNonce, convertArgs.totalInputValue);
            }
            results.outputValueA = outputValueA;
            results.outputValueB = outputValueB;
            results.isAsync = isAsync;
        }
        require(success, "Interaction Failed");
    }

    function convert(
        address bridgeAddress,
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata inputAssetB,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata outputAssetB,
        uint256 totalInputValue,
        uint256 interactionNonce,
        uint256 auxInputData // (auxData)
    )
        external
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        )
    {
        require(defiInteractions[interactionNonce].auxInputData == 0, "Rollup Contract: INTERACTION_ALREADY_EXISTS");

        uint256 ethPayments_slot;

        assembly {
            ethPayments_slot := ethPayments.slot
        }

        ConvertArgs memory convertArgs = ConvertArgs(
            bridgeAddress,
            inputAssetA,
            inputAssetB,
            outputAssetA,
            outputAssetB,
            totalInputValue,
            interactionNonce,
            auxInputData,
            ethPayments_slot
        );
        ConvertReturnValues memory results = _convert(convertArgs);
        outputValueA = results.outputValueA;
        outputValueB = results.outputValueB;
        isAsync = results.isAsync;
    }

    function getDefiInteractionBlockNumber(uint256 interactionNonce) external view returns (uint256 blockNumber) {
        blockNumber = interactionNonce / NUMBER_OF_BRIDGE_CALLS;
    }
}
