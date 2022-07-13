// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";

contract DonationBridge is BridgeBase {
    using SafeERC20 for IERC20;

    error EthTransferFailed();

    event ListedDonee(address donee, uint64 index);

    uint64 public nextDonee = 1;
    mapping(uint64 => address) public donees;

    constructor(address _rollupProcessor) BridgeBase(_rollupProcessor) {}

    function listDonee(address _donee) public returns (uint256) {
        uint64 id = nextDonee++;
        donees[id] = _donee;
        emit ListedDonee(_donee, id);
        return id;
    }

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
            uint256 outputValueA,
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
