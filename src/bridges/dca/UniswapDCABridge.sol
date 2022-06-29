// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";

import {BridgeBase} from "../base/BridgeBase.sol";
import {ErrorLib} from "../base/ErrorLib.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";

import {IWETH} from "../../interfaces/IWETH.sol";

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "../../interfaces/uniswapv3/ISwapRouter.sol";
import {BiDCABridge} from "./BiDCABridge.sol";

interface IChainlinkOracle {
    function latestRoundData()
        external
        view
        returns (
            uint80,
            int256,
            uint256,
            uint256,
            uint80
        );
}

contract UniswapDCABridge is BiDCABridge {
    using SafeERC20 for IERC20;
    bool public constant IS_TESTING = true;

    uint160 private constant SQRT_PRICE_LIMIT_X96 = 1461446703485210103287273052203988822378723970341;
    ISwapRouter public constant UNI_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    uint256 public constant MAX_AGE = 1 days; // Heartbeat of oracle is 24 hours.

    IChainlinkOracle public immutable ORACLE;

    constructor(
        address _rollupProcessor,
        address _assetA,
        address _assetB,
        uint256 _tickSize,
        address _oracle
    ) BiDCABridge(_rollupProcessor, _assetA, _assetB, _tickSize) {
        ORACLE = IChainlinkOracle(_oracle);

        IERC20(_assetA).safeApprove(address(UNI_ROUTER), type(uint256).max);
        IERC20(_assetB).safeApprove(address(UNI_ROUTER), type(uint256).max);
    }

    function rebalanceAndFillUniswap() public returns (int256, int256) {
        // Gaswise not ideal. But somewhat understandable.
        uint256 oraclePrice = getPrice();
        (int256 aFlow, int256 bFlow) = _rebalanceAndfill(0, 0, oraclePrice, true);
        (uint256 a, uint256 b) = getAvailable();

        if (a > 0 && b > 0) {
            (aFlow, bFlow) = _rebalanceAndfill(a, b, oraclePrice, true);
        }

        (a, b) = getAvailable();

        if (a > 0) {
            // Uniswap all A to B. Then compute the price, and use price-1 as the actual price. We want to undervalue a to ensure that we cover.
            uint256 bOffer = UNI_ROUTER.exactInput(
                ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(ASSET_A, uint24(3000), ASSET_B),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: a,
                    amountOutMinimum: 0 // (assetAInAssetB(a, oraclePrice, false) * 9950) / 10000
                })
            );

            // Compute the price that we got in the trade, rounded down.
            uint256 price = (bOffer * 1e18) / a;

            (aFlow, bFlow) = _rebalanceAndfill(0, bOffer, price, true);
        }

        if (b > 0) {
            // Uniswap all B to A. Then compute the price, and use price-1 as the actual price. We want to undervalue a to ensure that we cover.
            uint256 aOffer = UNI_ROUTER.exactInput(
                ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(ASSET_B, uint24(3000), ASSET_A),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: b,
                    amountOutMinimum: 0 // (assetBInAssetA(b, oraclePrice, false) * 9950) / 10000
                })
            );

            // Compute the price that we got in the trade, rounded up.
            uint256 price = (b * 1e18 + aOffer - 1) / aOffer;

            (aFlow, bFlow) = _rebalanceAndfill(aOffer, 0, price, true);
        }

        return (aFlow, bFlow);
    }

    function rebalanceTest(
        uint256 _a,
        uint256 _b,
        uint256 _price,
        bool _self,
        bool _transfer
    ) public returns (int256, int256) {
        // Only for testing
        (int256 flowA, int256 flowB) = _rebalanceAndfill(_a, _b, _price, _self);

        if (_transfer) {
            if (flowA > 0) {
                ASSET_A.safeTransferFrom(msg.sender, address(this), uint256(flowA));
            } else if (flowA < 0) {
                ASSET_A.safeTransfer(msg.sender, uint256(-flowA));
            }

            if (flowB > 0) {
                ASSET_B.safeTransferFrom(msg.sender, address(this), uint256(flowB));
            } else if (flowB < 0) {
                ASSET_B.safeTransfer(msg.sender, uint256(-flowB));
            }
        }
        return (flowA, flowB);
    }

    function getPrice() public virtual override(BiDCABridge) returns (uint256) {
        (, int256 answer, , uint256 updatedAt, ) = ORACLE.latestRoundData();
        if (!IS_TESTING && updatedAt + MAX_AGE < block.timestamp) {
            revert("Too old");
        }

        if (answer < 0) {
            revert("Negative price");
        }

        return uint256(answer);
    }
}
