// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {DonationBridge} from "../../../bridges/donation/DonationBridge.sol";

contract DonationBridgeE2ETest is BridgeTestBase {
    error InvalidDoneeAddress();
    error EthTransferFailed();

    address private constant DONEE = address(0xdead);

    DonationBridge private bridge;
    uint256 private bridgeAddressId;

    AztecTypes.AztecAsset private ethAsset;

    address public constant LUSD = 0x5f98805A4E8be255a32880FDeC7F6728C6568bA0;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant LQTY = 0x6DEA81C8171D0bA574754EF6F8b412F2Ed88c54D;
    address public constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;

    address[] internal tokens = [LUSD, DAI, WETH, LQTY, USDC, USDT];

    // Transferring eth to `address(this)` will run the following, costing much more gas than expected
    receive() external payable {
        uint256 a = 0;
        while (a < 10000) {
            a++;
        }
        if (a > 999) {
            revert("Err");
        }
    }

    function setUp() public {
        ethAsset = ROLLUP_ENCODER.getRealAztecAsset(address(0));
        bridge = new DonationBridge(address(ROLLUP_PROCESSOR));

        bridge.listDonee(DONEE);

        vm.deal(address(bridge), 0);
        vm.prank(MULTI_SIG);

        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 150000);
        bridgeAddressId = ROLLUP_PROCESSOR.getSupportedBridgesLength();
    }

    function testDonateEth(uint96 _amount) public {
        vm.assume(_amount > 0);
        vm.deal(address(ROLLUP_PROCESSOR), _amount);

        uint256 doneeBalanceBefore = DONEE.balance;

        uint256 bridgeCallData = ROLLUP_ENCODER.defiInteractionL2(
            bridgeAddressId,
            ethAsset,
            emptyAsset,
            emptyAsset,
            emptyAsset,
            1,
            _amount
        );

        ROLLUP_ENCODER.registerEventToBeChecked(bridgeCallData, ROLLUP_ENCODER.getNextNonce(), _amount, 0, 0, true, "");
        ROLLUP_ENCODER.processRollup();

        assertEq(DONEE.balance, doneeBalanceBefore + _amount, "Donee did not receive eth");
    }

    function testDonateERC20(uint96 _amount) public {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20Metadata token = IERC20Metadata(tokens[i]);
            uint8 decimals = token.decimals();
            uint256 amount = bound(_amount, 10**decimals, 1e6 * 10**decimals);

            if (!ROLLUP_ENCODER.isSupportedAsset(address(token))) {
                vm.prank(address(MULTI_SIG));
                ROLLUP_PROCESSOR.setSupportedAsset(address(token), 100000);
            }

            deal(address(token), address(ROLLUP_PROCESSOR), amount);

            uint256 doneeBalanceBefore = token.balanceOf(DONEE);

            uint256 bridgeCallData = ROLLUP_ENCODER.defiInteractionL2(
                bridgeAddressId,
                ROLLUP_ENCODER.getRealAztecAsset(address(token)),
                emptyAsset,
                emptyAsset,
                emptyAsset,
                1,
                amount
            );

            ROLLUP_ENCODER.registerEventToBeChecked(
                bridgeCallData,
                ROLLUP_ENCODER.getNextNonce(),
                _amount,
                0,
                0,
                true,
                ""
            );
            ROLLUP_ENCODER.processRollup();

            assertEq(token.balanceOf(DONEE), doneeBalanceBefore + amount, "Donee did not receive token");
        }
    }

    function testDonateEthTo0(uint96 _amount) public {
        vm.assume(_amount > 0);
        vm.deal(address(ROLLUP_PROCESSOR), _amount);

        uint256 bridgeCallData = ROLLUP_ENCODER.defiInteractionL2(
            bridgeAddressId,
            ethAsset,
            emptyAsset,
            emptyAsset,
            emptyAsset,
            2,
            _amount
        );

        bytes memory err = abi.encodePacked(ErrorLib.InvalidAuxData.selector);

        ROLLUP_ENCODER.registerEventToBeChecked(
            bridgeCallData,
            ROLLUP_ENCODER.getNextNonce(),
            _amount,
            0,
            0,
            false,
            err
        );
        ROLLUP_ENCODER.processRollup();
    }

    function testDonateEthToGasHeavy(uint96 _amount) public {
        vm.assume(_amount > 0);
        vm.deal(address(ROLLUP_PROCESSOR), _amount);

        uint256 doneeId = bridge.listDonee(address(this));

        uint256 bridgeCallData = ROLLUP_ENCODER.defiInteractionL2(
            bridgeAddressId,
            ethAsset,
            emptyAsset,
            emptyAsset,
            emptyAsset,
            uint64(doneeId),
            _amount
        );

        bytes memory err = abi.encodePacked(EthTransferFailed.selector);

        ROLLUP_ENCODER.registerEventToBeChecked(
            bridgeCallData,
            ROLLUP_ENCODER.getNextNonce(),
            _amount,
            0,
            0,
            false,
            err
        );
        ROLLUP_ENCODER.processRollup();
    }

    function testDonateWrongAsset(uint96 _amount) public {
        vm.assume(_amount > 0);
        vm.deal(address(ROLLUP_PROCESSOR), _amount);

        uint256 doneeId = bridge.listDonee(address(this));

        AztecTypes.AztecAsset memory fakeAsset = AztecTypes.AztecAsset({
            id: 1 | 0x20000000,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.VIRTUAL
        });

        uint256 bridgeCallData = ROLLUP_ENCODER.defiInteractionL2(
            bridgeAddressId,
            fakeAsset,
            emptyAsset,
            emptyAsset,
            emptyAsset,
            uint64(doneeId),
            _amount
        );
        bytes memory err = abi.encodePacked(ErrorLib.InvalidInputA.selector);
        ROLLUP_ENCODER.registerEventToBeChecked(
            bridgeCallData,
            ROLLUP_ENCODER.getNextNonce(),
            _amount,
            0,
            0,
            false,
            err
        );
        ROLLUP_ENCODER.processRollup();
    }

    function testInvalidDoneeAddress() public {
        vm.expectRevert(InvalidDoneeAddress.selector);
        bridge.listDonee(address(0));
    }
}
