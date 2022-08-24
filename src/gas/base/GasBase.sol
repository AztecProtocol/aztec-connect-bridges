// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";

contract GasBase {
    bytes4 private constant DEFI_BRIDGE_PROXY_CONVERT_SELECTOR = 0x4bd947a8;

    address public defiProxy;
    mapping(uint256 => uint256) public ethPayments;

    constructor(address _defiProxy) {
        defiProxy = _defiProxy;
    }

    receive() external payable {}

    fallback() external {}

    function getSupportedBridgesLength() external view returns (uint256) {
        return 0;
    }

    function getSupportedAssetsLength() external view returns (uint256) {
        return 0;
    }

    function receiveEthFromBridge(uint256 interactionNonce) external payable {
        ethPayments[interactionNonce] += msg.value;
    }

    struct Temps {
        uint256 paymentSlot;
        uint256 gasUsed;
        bool success;
    }

    function convert(
        address bridgeAddress,
        AztecTypes.AztecAsset memory inputAssetA,
        AztecTypes.AztecAsset memory inputAssetB,
        AztecTypes.AztecAsset memory outputAssetA,
        AztecTypes.AztecAsset memory outputAssetB,
        uint256 totalInputValue,
        uint256 interactionNonce,
        uint256 auxInputData, // (auxData)
        address rollupBeneficiary,
        uint256 gasLimit
    ) external returns (uint256) {
        Temps memory temps;
        {
            uint256 paymentSlot;
            assembly {
                mstore(temps, ethPayments.slot)
                //paymentSlot := ethPayments.slot
            }
        }

        temps.gasUsed = gasleft();
        (temps.success, ) = address(defiProxy).delegatecall{gas: gasLimit}(
            abi.encodeWithSelector(
                DEFI_BRIDGE_PROXY_CONVERT_SELECTOR,
                bridgeAddress,
                inputAssetA,
                inputAssetB,
                outputAssetA,
                outputAssetB,
                totalInputValue,
                interactionNonce,
                auxInputData,
                temps.paymentSlot,
                rollupBeneficiary
            )
        );
        temps.gasUsed -= gasleft();

        if (!temps.success) {
            revert("Failure, should only fail with OOM");
        }

        return temps.gasUsed;
    }
}
