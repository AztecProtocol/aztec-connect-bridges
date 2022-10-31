// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";

contract GasBase {
    bytes4 private constant DEFI_BRIDGE_PROXY_CONVERT_SELECTOR = 0x4bd947a8;

    address public defiProxy;
    mapping(uint256 => uint256) public ethPayments;

    constructor(address _defiProxy) {
        defiProxy = _defiProxy;
    }

    receive() external payable {}

    fallback() external {}

    function receiveEthFromBridge(uint256 _interactionNonce) external payable {
        ethPayments[_interactionNonce] += msg.value;
    }

    function convert(
        address _bridgeAddress,
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory _inputAssetB,
        AztecTypes.AztecAsset memory _outputAssetA,
        AztecTypes.AztecAsset memory _outputAssetB,
        uint256 _totalInputValue,
        uint256 _interactionNonce,
        uint256 _auxInputData,
        address _rollupBeneficiary,
        uint256 _gasLimit
    ) external {
        (bool success, bytes memory data) = address(defiProxy).delegatecall{gas: _gasLimit}(
            abi.encodeWithSelector(
                DEFI_BRIDGE_PROXY_CONVERT_SELECTOR,
                _bridgeAddress,
                _inputAssetA,
                _inputAssetB,
                _outputAssetA,
                _outputAssetB,
                _totalInputValue,
                _interactionNonce,
                _auxInputData,
                _getPaymentsSlot(),
                _rollupBeneficiary
            )
        );

        if (!success) {
            if (data.length == 0) revert("Revert without error message --> probably out of gas");
            assembly {
                revert(add(32, data), mload(data))
            }
        }
    }

    function getSupportedBridgesLength() external view returns (uint256) {
        return 0;
    }

    function getSupportedAssetsLength() external view returns (uint256) {
        return 0;
    }

    function _getPaymentsSlot() private returns (uint256 paymentSlot) {
        assembly {
            paymentSlot := ethPayments.slot
        }
    }
}
