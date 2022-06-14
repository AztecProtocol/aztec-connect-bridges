// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {Test} from "forge-std/Test.sol";
import {AztecTypes} from "./../../aztec/AztecTypes.sol";
import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {ICERC20} from "./../../bridges/compound/interfaces/ICERC20.sol";
import {CompoundBridge} from "./../../bridges/compound/CompoundBridge.sol";

contract CompoundTest is Test {
    // solhint-disable-next-line
    address public constant cETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;

    address[] public cTokens = [
        0xe65cdB6479BaC1e22340E4E755fAE7E509EcD06c, // cAAve
        0x6C8c6b02E7b2BE14d4fA6022Dfd6d75921D90E4E, // cBAT
        0x70e36f6BF80a52b3B46b3aF8e106CC0ed743E8e4, // cCOMP
        0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643, // cDAI
        0xFAce851a4921ce59e912d19329929CE6da6EB0c7, // cLINK
        0x95b4eF2869eBD94BEb4eEE400a99824BF5DC325b, // cMKR
        0x4B0181102A0112A2ef11AbEE5563bb4a3176c9d7, // cSUSHI
        0x12392F67bdf24faE0AF363c24aC620a2f67DAd86, // cTUSD
        0x35A18000230DA775CAc24873d00Ff85BccdeD550, // cUNI
        0x39AA39c021dfbaE8faC545936693aC917d5E7563, // cUSDC
        0x041171993284df560249B57358F931D9eB7b925D, // cUSDP
        0xf650C3d88D12dB855b8bf7D11Be6C55A4e07dCC9, // cUSDT
        0xccF4429DB6322D5C611ee964527D42E5d685DD6a, // cWBTC2
        0x80a2AE356fc9ef4305676f7a3E2Ed04e12C33946, // cYFI
        0xB3319f5D18Bc0D84dD1b4825Dcde5d5f7266d407 // cZRX
    ];

    DefiBridgeProxy internal defiBridgeProxy;
    RollupProcessor internal rollupProcessor;

    CompoundBridge internal compoundBridge;

    function setUp() public {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
        compoundBridge = new CompoundBridge(address(rollupProcessor));
    }

    function testETHDepositAndWithdrawal(uint88 _depositAmount) public {
        uint256 depositAmount;
        {
            uint8 underlyingDecimals = 18;
            uint256 exchangeRate = ICERC20(cETH).exchangeRateCurrent();
            uint256 oneCTokenInUnderlying = (exchangeRate * 1e18) / (10**(18 + underlyingDecimals - 8));
            emit log_named_uint("exchangeRate", exchangeRate);
            emit log_named_uint("oneCTokenInUnderlying", oneCTokenInUnderlying);
            depositAmount = bound(_depositAmount, oneCTokenInUnderlying, 10000 * 10**underlyingDecimals);
        }

        vm.deal(address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory depositInputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0x0000000000000000000000000000000000000000),
            assetType: AztecTypes.AztecAssetType.ETH
        });
        AztecTypes.AztecAsset memory depositOutputAssetA = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: cETH,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        // cETH minting
        (uint256 outputValueA, , ) = rollupProcessor.convert(
            address(compoundBridge),
            depositInputAssetA,
            empty,
            depositOutputAssetA,
            empty,
            depositAmount,
            1,
            0
        );

        assertGt(outputValueA, 0, "cETH received is zero");
        assertEq(outputValueA, IERC20(cETH).balanceOf(address(rollupProcessor)), "cToken balance not matching");

        uint256 redeemAmount = outputValueA;
        AztecTypes.AztecAsset memory redeemInputAssetA = depositOutputAssetA;
        AztecTypes.AztecAsset memory redeemOutputAssetA = depositInputAssetA;

        // withdrawing ETH (cETH burning)
        (outputValueA, , ) = rollupProcessor.convert(
            address(compoundBridge),
            redeemInputAssetA,
            empty,
            redeemOutputAssetA,
            empty,
            redeemAmount,
            1,
            1
        );

        // ETH withdrawn should be approximately equal to ETH deposited
        // --> the amounts are not the same due to rounding errors in Compound
        assertLt(
            depositAmount - outputValueA,
            1e10,
            "amount of ETH withdrawn is not similar to the amount of ETH deposited"
        );
        assertLt(
            IERC20(cETH).balanceOf(address(rollupProcessor)),
            outputValueA,
            "cEther balance not reduced by withdraw"
        );
    }

    function testERC20DepositAndWithdrawal(uint88 _depositAmount) public {
        // Note: if Foundry implements parametrized tests remove this for loop,
        // stop calling setup() from _depositAndWithdrawERC20 and use the native
        // functionality
        for (uint256 i; i < cTokens.length; ++i) {
            _depositAndWithdrawERC20(cTokens[i], _depositAmount);
        }
    }

    function testInvalidCaller() public {
        AztecTypes.AztecAsset memory empty;

        vm.expectRevert(CompoundBridge.InvalidCaller.selector);
        compoundBridge.convert(empty, empty, empty, empty, 0, 0, 0, address(0));
    }

    function testIncorrectInputAsset() public {
        AztecTypes.AztecAsset memory empty;

        AztecTypes.AztecAsset memory ethAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0x0000000000000000000000000000000000000000),
            assetType: AztecTypes.AztecAssetType.ETH
        });

        vm.prank(address(rollupProcessor));
        vm.expectRevert(CompoundBridge.IncorrectInputAsset.selector);
        compoundBridge.convert(ethAsset, empty, empty, empty, 0, 0, 1, address(0));
    }

    function testIncorrectOutputAsset() public {
        AztecTypes.AztecAsset memory empty;

        vm.prank(address(rollupProcessor));
        vm.expectRevert(CompoundBridge.IncorrectOutputAsset.selector);
        compoundBridge.convert(empty, empty, empty, empty, 0, 0, 0, address(0));
    }

    function testIncorrectAuxData() public {
        AztecTypes.AztecAsset memory empty;

        vm.prank(address(rollupProcessor));
        vm.expectRevert(CompoundBridge.IncorrectAuxData.selector);
        compoundBridge.convert(empty, empty, empty, empty, 0, 0, 2, address(0));
    }

    function _depositAndWithdrawERC20(address _cToken, uint256 _depositAmount) private {
        setUp();
        address underlyingToken = ICERC20(_cToken).underlying();
        uint256 depositAmount;
        {
            uint8 underlyingDecimals = 18;
            uint256 exchangeRate = ICERC20(_cToken).exchangeRateCurrent();
            uint256 oneCTokenInUnderlying = (exchangeRate * 1e18) / (10**(18 + underlyingDecimals - 8));
            depositAmount = bound(_depositAmount, oneCTokenInUnderlying, 10000 * 10**underlyingDecimals);
        }

        deal(underlyingToken, address(rollupProcessor), depositAmount);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory depositInputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: underlyingToken,
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        AztecTypes.AztecAsset memory depositOutputAssetA = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: _cToken,
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        // cToken minting
        (uint256 outputValueA, , ) = rollupProcessor.convert(
            address(compoundBridge),
            depositInputAssetA,
            empty,
            depositOutputAssetA,
            empty,
            depositAmount,
            0,
            0
        );

        assertGt(outputValueA, 0, "cToken received is zero");
        assertEq(outputValueA, IERC20(_cToken).balanceOf(address(rollupProcessor)), "cToken balance not matching");

        uint256 redeemAmount = outputValueA;
        AztecTypes.AztecAsset memory redeemInputAssetA = depositOutputAssetA;
        AztecTypes.AztecAsset memory redeemOutputAssetA = depositInputAssetA;

        // withdrawing underlying (cToken burning)
        (outputValueA, , ) = rollupProcessor.convert(
            address(compoundBridge),
            redeemInputAssetA,
            empty,
            redeemOutputAssetA,
            empty,
            redeemAmount,
            1,
            1
        );

        // token withdrawn should be approximately equal to token deposited
        // --> the amounts are not exactly the same due to rounding errors in Compound
        assertLt(
            depositAmount - outputValueA,
            1e10,
            "amount of underlying Token withdrawn is not similar to the amount of cToken deposited"
        );
        assertLt(
            IERC20(_cToken).balanceOf(address(rollupProcessor)),
            outputValueA,
            "balance not decreased by withdraw"
        );
    }
}
