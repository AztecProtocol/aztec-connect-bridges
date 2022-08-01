// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {BridgeBase} from "../base/BridgeBase.sol";
import {ISubsidy} from "../../aztec/interfaces/ISubsidy.sol";

/**
 * @title An example bridge contract.
 * @author Aztec Team
 * @notice You can use this contract to immediately get back what you've deposited.
 * @dev This bridge demonstrates the flow of assets in the convert function. This bridge simply returns what has been
 *      sent to it.
 */
contract ExampleBridgeContract is BridgeBase {
    ISubsidy immutable SUBSIDY;

    /**
     * @notice Set address of rollup processor
     * @param _rollupProcessor Address of rollup processor
     */
    constructor(address _rollupProcessor, ISubsidy _subsidy) BridgeBase(_rollupProcessor) {
        SUBSIDY = _subsidy;

        address dai = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
        // We set gas usage in the subsidy contract
        // We only want to incentivize the bridge when input and output token is Dai
        SUBSIDY.setGasUsage(_computeCriteria(dai, dai), 50000);
    }

    /**
     * @notice A function which returns an _totalInputValue amount of _inputAssetA
     * @param _inputAssetA - Arbitrary ERC20 token
     * @param _outputAssetA - Equal to _inputAssetA
     * @param _rollupBeneficiary - Address of the contract which receives subsidy in case subsidy was set for a given
     *                             criteria
     * @return outputValueA - the amount of output asset to return
     * @dev In this case _outputAssetA equals _inputAssetA
     */
    function convert(
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory,
        AztecTypes.AztecAsset memory _outputAssetA,
        AztecTypes.AztecAsset memory,
        uint256 _totalInputValue,
        uint256,
        uint64,
        address _rollupBeneficiary
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
        if (_outputAssetA.erc20Address != _inputAssetA.erc20Address) revert ErrorLib.InvalidOutputA();
        // Return the input value of input asset
        outputValueA = _totalInputValue;
        // Approve rollup processor to take input value of input asset
        IERC20(_outputAssetA.erc20Address).approve(ROLLUP_PROCESSOR, _totalInputValue);

        // Pay out subsidy to the rollupBeneficiary
        SUBSIDY.claimSubsidy(
            _computeCriteria(_inputAssetA.erc20Address, _outputAssetA.erc20Address),
            _rollupBeneficiary
        );
    }

    function _computeCriteria(address _input, address _output) private pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_input, _output)));
    }
}
