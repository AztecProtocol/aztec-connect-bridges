// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";

/**
 * @notice Bridge that allows users to collectively donate funds to an L1 address
 * @author Lasse Herskind (LHerskind on GitHub)
 */
contract DonationBridge is BridgeBase {
    using SafeERC20 for IERC20;

    error EthTransferFailed();

    event ListedDonee(address donee, uint64 index);

    // Starts at 1 to revert if users forget to provide auxdata.
    uint64 public nextDonee = 1;

    // Maps id to a donee
    mapping(uint64 => address) public donees;

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    /**
     * @notice Lists a new Donee on the bridge
     * @param _donee The address to add as a donee
     * @return id The id of the new donee
     */
    function listDonee(address _donee) public returns (uint256) {
        uint64 id = nextDonee++;
        donees[id] = _donee;
        emit ListedDonee(_donee, id);
        return id;
    }

    /**
     * @notice Transfers `_inputAssetA` to `donees[_auxData]`
     * @param _inputAssetA The asset to donate
     * @param _inputValue The amount to donate
     * @param _auxData The id of the donee
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        uint256 _inputValue,
        uint256,
        uint64 _auxData,
        address
    )
        external
        payable
        override(BridgeBase)
        onlyRollup
        returns (
            uint256,
            uint256,
            bool
        )
    {
        address receiver = donees[_auxData];

        if (receiver == address(0)) {
            revert ErrorLib.InvalidAuxData();
        }

        if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
            //solhint-disable-next-line
            (bool success, ) = payable(receiver).call{gas: 30000, value: _inputValue}("");
            if (!success) revert EthTransferFailed();
        } else if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20) {
            IERC20(_inputAssetA.erc20Address).safeTransfer(receiver, _inputValue);
        } else {
            revert ErrorLib.InvalidInputA();
        }
        return (0, 0, false);
    }
}
