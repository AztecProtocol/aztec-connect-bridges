// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";

/**
 * @title An example bridge contract.
 * @author Aztec Team
 * @notice You can use this contract to immediately get back what you've deposited.
 * @dev This bridge demonstrates the flow of assets in the convert function. This bridge simply returns what has been
 *      sent to it.
 */
contract ExampleBridgeContract is BridgeBase {
    /**
     * @notice Set address of RollupProcessor.sol.
     * @param _rollupProcessor Address of RollupProcessor.sol
     */
    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    /**
     * @notice A function which returns an _inputValue amount of _inputAssetA.
     * @param _inputAssetA - Arbitrary ERC20 token.
     * @return outputValueA - the amount of output asset to return
     * @dev In this case _outputAssetA equals _inputAssetA.
     */
    function convert(
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory,
        AztecTypes.AztecAsset memory,
        AztecTypes.AztecAsset memory,
        uint256 _inputValue,
        uint256,
        uint64,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256,
            bool
        )
    {
        // Check the input asset is ERC20
        if (_inputAssetA.assetType != AztecTypes.AztecAssetType.ERC20) revert ErrorLib.InvalidInputA();
        // Return the input value of input asset
        outputValueA = _inputValue;
        // Approve rollup processor to take input value of input asset
        IERC20(_inputAssetA.erc20Address).approve(ROLLUP_PROCESSOR, _inputValue);
    }
}
