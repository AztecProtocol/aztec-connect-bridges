// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {Test} from "forge-std/Test.sol";
import {AztecTypes} from "rollup-encoder/libraries/AztecTypes.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {IWETH} from "../../../interfaces/IWETH.sol";

import {ISwapRouter} from "../../../interfaces/uniswapv3/ISwapRouter.sol";

import {BiDCABridge} from "../../../bridges/dca/BiDCABridge.sol";
import {UniswapDCABridge} from "../../../bridges/dca/UniswapDCABridge.sol";

contract BiDCABridgeArberTest is Test {
    using SafeERC20 for IERC20;
    using SafeERC20 for ERC20;

    struct Sums {
        uint256 summedA;
        uint256 summedAInv;
        uint256 summedB;
        uint256 summedBInv;
    }

    address private constant SEARCHER = address(0xdeadbeef);

    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    uint160 private constant SQRT_PRICE_LIMIT_X96 = 1461446703485210103287273052203988822378723970341;

    IWETH internal constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address internal constant ORACLE = 0x773616E4d11A78F511299002da57A0a94577F1f4;

    UniswapDCABridge internal bridge;
    IERC20 internal assetA;
    IERC20 internal assetB;

    AztecTypes.AztecAsset internal emptyAsset;
    AztecTypes.AztecAsset internal aztecAssetA;
    AztecTypes.AztecAsset internal aztecAssetB;

    receive() external payable {}

    function receiveEthFromBridge(uint256 _interactionNonce) public payable {}

    function setUp() public {
        // Preparation
        assetA = IERC20(address(0x6B175474E89094C44Da98b954EedeAC495271d0F));
        assetB = IERC20(address(WETH));
        bridge = new UniswapDCABridge(address(this), 1 days, 10);
        aztecAssetA =
            AztecTypes.AztecAsset({id: 1, erc20Address: address(assetA), assetType: AztecTypes.AztecAssetType.ERC20});
        aztecAssetB =
            AztecTypes.AztecAsset({id: 2, erc20Address: address(assetB), assetType: AztecTypes.AztecAssetType.ERC20});
        vm.label(address(assetA), "DAI");
        vm.label(address(assetB), "WETH");

        vm.deal(address(bridge), 0);
        vm.label(address(bridge), "Bridge");

        _movePrice(0, 1e18); // Do trade on uniswap and update oracle price

        vm.deal(SEARCHER, 0);
    }

    function testNoDeposits() public {
        vm.expectRevert(BiDCABridge.NoDeposits.selector);
        bridge.getAvailable();
    }

    function testSearcherFinalise() public {
        uint256 daiDeposit = 5000e18;
        uint256 nonce = 0;

        // Create a position, 5000 dai -> eth over 2 day
        deal(address(assetA), address(bridge), daiDeposit);
        bridge.convert(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, daiDeposit, 0, 2, address(0));

        vm.warp(block.timestamp + 3 days); // next tick + 2 days

        bridge.rebalanceAndFillUniswap(type(uint256).max);
        (uint256 acc,) = bridge.getAccumulated(nonce);

        uint256 balanceBefore = WETH.balanceOf(SEARCHER);

        vm.prank(address(this), SEARCHER); // msg.sender = this, tx.origin = SEARCHER
        (uint256 outA,,) = bridge.finalise(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, nonce, 0);

        assertEq(acc, outA + WETH.balanceOf(SEARCHER), "Bal matches");

        emit log_named_decimal_uint("Balance before", balanceBefore, 18);
        emit log_named_decimal_uint("Balance after ", WETH.balanceOf(SEARCHER), 18);
    }

    function testSearcherSwap() public {
        uint256 daiDeposit = 5000e18;

        // Create a position, 5000 dai -> eth over 2 day
        deal(address(assetA), address(bridge), daiDeposit);
        bridge.convert(aztecAssetA, emptyAsset, aztecAssetB, emptyAsset, daiDeposit, 0, 2, address(0));

        vm.warp(block.timestamp + 3 days); // need next tick + 2

        // Update oracle price such that Eth is cheaper than uniswap.
        _setPrice((bridge.getPrice() * 995) / 1000);

        // Then we want to swap directly.
        vm.startPrank(SEARCHER);
        deal(address(WETH), SEARCHER, 10 ether);
        WETH.approve(address(bridge), type(uint256).max);
        uint256 balanceBefore = WETH.balanceOf(SEARCHER);

        // Trade eth -> dai with the bridge
        bridge.rebalanceAndFill(0, 10 ether);

        // Trade dai -> usdc -> eth on uniswap
        ISwapRouter uniRouter = bridge.UNI_ROUTER();
        assetA.approve(address(uniRouter), type(uint256).max);
        uniRouter.exactInput(
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(address(assetA), uint24(100), USDC, uint24(500), address(assetB)),
                recipient: SEARCHER,
                deadline: block.timestamp,
                amountIn: daiDeposit,
                amountOutMinimum: 0
            })
        );
        vm.stopPrank();

        emit log_named_decimal_uint("Balance before", balanceBefore, 18);
        emit log_named_decimal_uint("Balance after ", WETH.balanceOf(SEARCHER), 18);
    }

    function _setPrice(uint256 _newPrice) internal {
        bytes memory returnValue = abi.encode(uint80(0), int256(_newPrice), uint256(0), block.timestamp, uint80(0));
        vm.mockCall(ORACLE, "", returnValue);

        emit log_named_decimal_uint("Setting Price", _newPrice, 18);

        assertEq(bridge.getPrice(), _newPrice, "Price not updated correctly");
    }

    function _movePrice(uint256 _amountAToB, uint256 _amountBToA) internal {
        ISwapRouter uniRouter = bridge.UNI_ROUTER();

        address user = address(0xdead);
        vm.startPrank(user);

        if (_amountAToB > 0) {
            deal(address(assetA), user, _amountAToB);
            assetA.approve(address(uniRouter), type(uint256).max);

            uint256 b = uniRouter.exactInput(
                ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(address(assetA), uint24(100), USDC, uint24(500), address(assetB)),
                    recipient: user,
                    deadline: block.timestamp,
                    amountIn: _amountAToB,
                    amountOutMinimum: 0
                })
            );

            uint256 price = (b * 1e18) / _amountAToB;
            _setPrice(price);
        }

        if (_amountBToA > 0) {
            deal(address(assetB), user, _amountBToA);
            assetB.approve(address(uniRouter), type(uint256).max);

            uint256 a = uniRouter.exactInput(
                ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(address(assetB), uint24(500), USDC, uint24(100), address(assetA)),
                    recipient: user,
                    deadline: block.timestamp,
                    amountIn: _amountBToA,
                    amountOutMinimum: 0
                })
            );
            uint256 price = (_amountBToA * 1e18 + a - 1) / a;
            _setPrice(price);
        }
        vm.stopPrank();
    }
}
