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
        uint256 paymentSlot;
        assembly {
            paymentSlot := ethPayments.slot
        }

        (bool success, ) = address(defiProxy).delegatecall{gas: _gasLimit}(
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
                paymentSlot,
                _rollupBeneficiary
            )
        );

        if (!success) {
            revert("Failure, should only fail with OOM");
        }
    }

    function getSupportedBridgesLength() external view returns (uint256) {
        return 0;
    }

    function getSupportedAssetsLength() external view returns (uint256) {
        return 0;
    }
}
