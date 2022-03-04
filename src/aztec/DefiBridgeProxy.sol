// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec
pragma solidity >=0.8.4 <0.8.11;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IDefiBridge} from "../interfaces/IDefiBridge.sol";
import {AztecTypes} from "./AztecTypes.sol";

import {TokenTransfers} from "../libraries/TokenTransfers.sol";

import "../../lib/ds-test/src/test.sol";

contract DefiBridgeProxy is DSTest {
    bytes4 private constant BALANCE_OF_SELECTOR = 0x70a08231; // bytes4(keccak256('balanceOf(address)'));
    bytes4 private constant TRANSFER_SELECTOR = 0xa9059cbb; // bytes4(keccak256('transfer(address,uint256)'));
    bytes4 private constant DEPOSIT_SELECTOR = 0xb6b55f25; // bytes4(keccak256('deposit(uint256)'));
    bytes4 private constant WITHDRAW_SELECTOR = 0x2e1a7d4d; // bytes4(keccak256('withdraw(uint256)'));
    bytes4 private constant TRANSFER_FROM_SELECTOR = 0x23b872dd; // bytes4(keccak256('transferFrom(address,address,uint256)'));

    error DEFI_BRIDGE_PROXY_TRANSFER_FAILED();
    error INCORRECT_ASSET_VALUE();
    error ASYNC_NONZERO_OUTPUT_VALUES(
        uint256 outputValueA,
        uint256 outputValueB
    );
    error INSUFFICIENT_ETH_PAYMENT();

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

    /**
     * @dev Use interaction result data to pull tokens into DefiBridgeProxy
     * @param asset The AztecAsset being targetted
     * @param outputValue The claimed output value provided by the bridge
     * @param interactionNonce The defi interaction nonce of the interaction
     * @param bridgeContract Address of the defi bridge contract
     * @param ethPaymentsSlot The slot value of the `ethPayments` storage mapping in RollupProcessor.sol!
     * More details on ethPaymentsSlot are in the comments for the `convert` function
     */
    function recoverTokens(
        AztecTypes.AztecAsset memory asset,
        uint256 outputValue,
        uint256 interactionNonce,
        address bridgeContract,
        uint256 ethPaymentsSlot
    ) internal {
        if (asset.assetType == AztecTypes.AztecAssetType.ETH) {
            uint256 ethPayment;
            uint256 ethPaymentsSlotBase;
            assembly {
                mstore(0x00, interactionNonce)
                mstore(0x20, ethPaymentsSlot)
                ethPaymentsSlotBase := keccak256(0x00, 0x40)
                ethPayment := sload(ethPaymentsSlotBase) // ethPayment = ethPayments[interactionNonce]
            }
            if (outputValue != ethPayment) {
                revert INSUFFICIENT_ETH_PAYMENT();
            }
            assembly {
                sstore(ethPaymentsSlotBase, 0) // ethPayments[interactionNonce] = 0;
            }
        } else if (
            asset.assetType == AztecTypes.AztecAssetType.ERC20 &&
            outputValue > 0
        ) {
            TokenTransfers.safeTransferFrom(
                asset.erc20Address,
                bridgeContract,
                address(this),
                outputValue
            );
        }
    }

    /**
     * @dev Convert input assets into output assets via calling a defi bridge contract
     * @param bridgeAddress Address of the defi bridge contract
     * @param inputAssetA First input asset
     * @param inputAssetB Second input asset. Is either VIRTUAL or NOT_USED (checked by RollupProcessor)
     * @param outputAssetA First output asset
     * @param outputAssetB Second output asset
     * @param totalInputValue The total amount of inputAssetA to be sent to the bridge
     * @param interactionNonce Integer that is unique for a given defi interaction
     * @param auxInputData Optional custom data to be sent to the bridge (defined in the L2 SNARK circuits when creating claim notes)
     * @param ethPaymentsSlot The slot value of the `ethPayments` storage mapping in RollupProcessor.sol!
     * We assume this contract is called from the RollupProcessor via `delegateCall`,
     * if not... this contract behaviour is undefined! So don't do that.
     * The idea here is that, if the defi bridge has returned native ETH, they will do so via calling
     * `RollupProcessor.receiveEthPayment(uint256 interactionNonce)`.
     * To summarise the issue, we must solve for the following:
     * 1. We need to be able to read the `ethPayments` state variable to determine how much Eth has been sent (and reset it)
     * 2. We must encapsulate the entire defi interaction flow via a 'delegatecall' so that we can safely revert
     *    all token/eth transfers if the defi interaction fails, *without* throwing the entire rollup transaction
     * 3. We don't want to directly call `delegateCall` on RollupProcessor.sol to minimise the attack surface against delegatecall re-entrancy exploits
     *
     * Solution is to pass the ethPayments.slot storage slot in as a param during the delegateCall and update in assembly via `sstore`
     * We could achieve the same effect via getters/setters on the function, but that would be expensive as that would trigger additional `call` opcodes.
     * We could *also* just hard-code the slot value, but that is quite brittle as
     * any re-ordering of storage variables during development would require updating the hardcoded constant
     *
     * @return outputValueA outputvalueB isAsync
     * outputValueA = the number of outputAssetA tokens we must recover from the bridge
     * outputValueB = the number of outputAssetB tokens we must recover from the bridge
     * isAsync describes whether the defi interaction has instantly resolved, or if the interaction must be finalised in a future Eth block
     * if isAsync == true, outputValueA and outputValueB must both equal 0
     */
    function convert(
        address bridgeAddress,
        AztecTypes.AztecAsset memory inputAssetA,
        AztecTypes.AztecAsset memory inputAssetB,
        AztecTypes.AztecAsset memory outputAssetA,
        AztecTypes.AztecAsset memory outputAssetB,
        uint256 totalInputValue,
        uint256 interactionNonce,
        uint256 auxInputData, // (auxData)
        uint256 ethPaymentsSlot
    )
        external
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        )
    {

        if (inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
            // Transfer totalInputValue to the bridge contract if erc20. ETH is sent on call to convert.
            TokenTransfers.safeTransferTo(
                inputAssetA.erc20Address,
                bridgeAddress,
                totalInputValue
            );
        }

        if (inputAssetB.assetType == AztecTypes.AztecAssetType.ERC20) {
            // Transfer totalInputValue to the bridge contract if erc20. ETH is sent on call to convert.
            TokenTransfers.safeTransferTo(inputAssetB.erc20Address, bridgeAddress, totalInputValue);
        }

        // Call bridge.convert(), which will return output values for the two output assets.
        // If input is ETH, send it along with call to convert.

        IDefiBridge bridgeContract = IDefiBridge(bridgeAddress);
        (outputValueA, outputValueB, isAsync) = bridgeContract.convert{
            value: inputAssetA.assetType == AztecTypes.AztecAssetType.ETH
                ? totalInputValue
                : 0
        }(
            inputAssetA,
            inputAssetB,
            outputAssetA,
            outputAssetB,
            totalInputValue,
            interactionNonce,
            uint64(auxInputData)
        );

        if (isAsync) {
            if (outputValueA > 0 || outputValueB > 0) {
                revert ASYNC_NONZERO_OUTPUT_VALUES(outputValueA, outputValueB);
            }
        } else {
            address bridgeAddressCopy = bridgeAddress; // stack overflow workaround
            recoverTokens(
                outputAssetA,
                outputValueA,
                interactionNonce,
                bridgeAddressCopy,
                ethPaymentsSlot
            );

            recoverTokens(
                outputAssetB,
                outputValueB,
                interactionNonce,
                bridgeAddressCopy,
                ethPaymentsSlot
            );
        }
    }
}
