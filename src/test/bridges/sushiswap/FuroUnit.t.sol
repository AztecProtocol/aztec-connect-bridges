// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

import {FuroBridge} from "../../../bridges/sushiswap/furo/FuroBridge.sol";

interface IBento {
    function toAmount(
        IERC20,
        uint256,
        bool
    ) external view returns (uint256);

    function toShare(
        IERC20,
        uint256,
        bool
    ) external view returns (uint256);
}

contract FuroUnitTest is Test {
    // custom errors for Furo
    error NotSenderOrRecipient();
    error InvalidStartTime();
    error InvalidEndTime();
    error InvalidWithdrawTooMuch();
    error NotSender();
    error Overflow();

    AztecTypes.AztecAsset internal emptyAsset;

    address private rollupProcessor;
    FuroBridge private bridge;

    IERC20 public constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);

    function setUp() public {
        rollupProcessor = address(this);

        bridge = new FuroBridge(rollupProcessor);

        vm.deal(address(bridge), 0);
        vm.label(address(bridge), "Furo Bridge");
        bridge.preApprove(address(DAI));
    }

    function testCreateAndClaim(
        uint256 _amount,
        uint256 _length,
        uint256 _time,
        uint256 _claimFraction
    ) public {
        uint256 amount = bound(_amount, 1e18, 1e26);
        uint256 length = bound(_length, 1, 30 days);
        uint256 time = bound(_time, 1, length);
        uint256 claimFraction = bound(_claimFraction, 1, 100);

        uint256 virtualShares = _createStream(amount, 1, length);
        assertEq(
            virtualShares,
            bridge.FURO().getStream(bridge.nonceToStream(1)).depositedShares,
            "Invalid number of shares"
        );

        vm.warp(block.timestamp + time);

        (, uint256 recipientShares) = bridge.FURO().streamBalanceOf(bridge.nonceToStream(1));
        uint256 claimShares = (recipientShares * claimFraction) / 100;

        uint256 recipientValue = IBento(bridge.FURO().bentoBox()).toAmount(DAI, claimShares, false);
        uint256 received = _claimFromStream(claimShares, 1, 2);

        assertEq(received, recipientValue, "Invalid amount received");
    }

    function testCreateAndClaimFixedAmount() public {
        testCreateAndClaim(1000e18, 3600, 3600, 100);
    }

    function testCreateAndMultipleClaims() public {
        revert("Implement");
    }

    function testMultipleCreatesAndClaims() public {
        revert("Implement");
    }

    function _createStream(
        uint256 _amount,
        uint256 _interactionNonce,
        uint256 _time
    ) internal returns (uint256) {
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(DAI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: _interactionNonce,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.VIRTUAL
        });

        deal(address(DAI), address(bridge), _amount);

        uint256 expectOutput = IBento(bridge.FURO().bentoBox()).toShare(DAI, _amount, false);

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
            inputAssetA,
            emptyAsset,
            outputAssetA,
            emptyAsset,
            _amount,
            _interactionNonce,
            uint64((block.timestamp << 32) + (block.timestamp + _time)),
            address(0)
        );

        assertEq(outputValueA, expectOutput, "Create non-matching A");
        assertEq(outputValueB, 0, "Non zero B");
        assertFalse(isAsync, "Was async");

        return outputValueA;
    }

    function _claimFromStream(
        uint256 _amount,
        uint256 _vId,
        uint256 _interactionNonce
    ) internal returns (uint256) {
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: _vId,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.VIRTUAL
        });
        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(DAI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        uint256 expectOutput = IBento(bridge.FURO().bentoBox()).toAmount(DAI, _amount, false);

        (uint256 outputValueA, uint256 outputValueB, bool isAsync) = bridge.convert(
            inputAssetA,
            emptyAsset,
            outputAssetA,
            emptyAsset,
            _amount,
            _interactionNonce,
            0,
            address(0)
        );

        assertEq(outputValueA, expectOutput, "Claim non-matching A");
        assertEq(outputValueB, 0, "Non zero B");
        assertFalse(isAsync, "Was async");

        DAI.transferFrom(address(bridge), rollupProcessor, outputValueA);

        return outputValueA;
    }
}
