// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.8.0 <=0.8.10;
pragma abicoder v2;

import {IDefiBridge} from "../interfaces/IDefiBridge.sol";
import {IERC20} from "../interfaces/IERC20Permit.sol";
import {DefiBridgeProxy} from "./DefiBridgeProxy.sol";
import {AztecTypes} from "./AztecTypes.sol";

import "../../lib/ds-test/src/test.sol";

import { console } from 'forge-std/console.sol';

contract RollupProcessor is DSTest {
    DefiBridgeProxy private bridgeProxy;

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

    uint256 private constant NUMBER_OF_BRIDGE_CALLS = 32;
    bytes4 private constant TRANSFER_FROM_SELECTOR = 0x23b872dd; // bytes4(keccak256('transferFrom(address,address,uint256)'));
    mapping(uint256 => uint256) ethPayments;
    mapping(address => uint256) bridgeGasLimits;

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
    //       uint256 ethPaymentsSlot)
    // N.B. this is the selector of the 'convert' function of the DefiBridgeProxy contract.
    //      This has a different interface to the IDefiBridge.convert function
    bytes4 private constant DEFI_BRIDGE_PROXY_CONVERT_SELECTOR = 0xffd8e7b7;
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
            uint256 totalInputValue
        );

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

    function transferTokensAsync(
        address bridgeContract,
        AztecTypes.AztecAsset memory asset,
        uint256 outputValue,
        uint256 interactionNonce
    ) internal {
        if (asset.assetType == AztecTypes.AztecAssetType.ETH) {
            require(
                outputValue == ethPayments[interactionNonce],
                "Rollup Processor: INSUFFICEINT_ETH_PAYMENT"
            );
            ethPayments[interactionNonce] = 0;
        } else if (
            asset.assetType == AztecTypes.AztecAssetType.ERC20 &&
            outputValue > 0
        ) {
            address tokenAddress = asset.erc20Address;
            bool success;

            assembly {
                // call token.transferFrom(bridgeAddressId, this, outputValue)
                let mPtr := mload(0x40)
                mstore(mPtr, TRANSFER_FROM_SELECTOR)
                mstore(add(mPtr, 0x04), bridgeContract)
                mstore(add(mPtr, 0x24), address())
                mstore(add(mPtr, 0x44), outputValue)
                success := call(gas(), tokenAddress, 0, mPtr, 0x64, 0x00, 0x20)
                if iszero(success) {
                    returndatacopy(0, 0, returndatasize())
                    revert(0x00, returndatasize())
                }
            }
        }

        // VIRTUAL Assets are not transfered.
    }

    function processAsyncDefiInteraction(uint256 interactionNonce) external returns (bool completed) {
        // call canFinalise on the bridge
        // call finalise on the bridge
        DefiInteraction storage interaction = defiInteractions[
            interactionNonce
        ];
        require(
            interaction.bridgeAddress != address(0),
            "Rollup Contract: UNKNOWN_NONCE"
        );

        (uint256 outputValueA, uint256 outputValueB, bool interactionComplete) = IDefiBridge(
            interaction.bridgeAddress
        ).finalise(
                interaction.inputAssetA,
                interaction.inputAssetB,
                interaction.outputAssetA,
                interaction.outputAssetB,
                interaction.interactionNonce,
                uint64(interaction.auxInputData)
            );
        completed = interactionComplete;

        if (
            outputValueB > 0 &&
            interaction.outputAssetB.assetType ==
            AztecTypes.AztecAssetType.NOT_USED
        ) {
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

    function _convert(ConvertArgs memory convertArgs) private returns (
            ConvertReturnValues memory results
        ) {
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
        uint256 gas = bridgeGasLimits[convertArgs.bridgeAddress]  > 0 ? bridgeGasLimits[convertArgs.bridgeAddress]: uint256(150000000);

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
                convertArgs.ethPaymentsSlot
            )
        );
        results = ConvertReturnValues(0, 0, false);

        if (success) {
            (uint256 outputValueA, uint256 outputValueB, bool isAsync) = abi.decode(
                result,
                (uint256, uint256, bool)
            );
            if (!isAsync) {
                emit DefiBridgeProcessed (
                    0,
                    convertArgs.interactionNonce,
                    convertArgs.totalInputValue,
                    outputValueA,
                    outputValueB,
                    true
                );
            } else {
                emit AsyncDefiBridgeProcessed (
                    0,
                    convertArgs.interactionNonce,
                    convertArgs.totalInputValue
                );
            }
            results.outputValueA = outputValueA;
            results.outputValueB = outputValueB;
            results.isAsync = isAsync;
        }
        require(success, 'Interaction Failed');

        // else {


        //     emit DefiBridgeProcessed(
        //     0,
        //     interactionNonce,
        //     totalInputValue,
        //     totalInputValue,
        //     inputAssetB.NOT_USED || inputAssetB.,
        //     success
        // );
        // }
        // TODO: Should probaby emit an event for failed?
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
        require(
            defiInteractions[interactionNonce].auxInputData == 0,
            "Rollup Contract: INTERACTION_ALREADY_EXISTS"
        );

        uint256 ethPayments_slot;

        assembly {
            ethPayments_slot := ethPayments.slot
        }

        ConvertArgs memory convertArgs = ConvertArgs(bridgeAddress, inputAssetA, inputAssetB, outputAssetA, outputAssetB, totalInputValue, interactionNonce, auxInputData, ethPayments_slot);
        (ConvertReturnValues memory results) = _convert(convertArgs);
        outputValueA = results.outputValueA;
        outputValueB = results.outputValueB;
        isAsync = results.isAsync;
    }

    function getDefiInteractionBlockNumber(uint256 interactionNonce) external view returns (uint256 blockNumber) {
        blockNumber = interactionNonce / NUMBER_OF_BRIDGE_CALLS;
    }
}
