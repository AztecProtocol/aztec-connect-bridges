// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {IWETH} from "../../interfaces/IWETH.sol";
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

/**
 * @notice DCA bridge that uses chainlink as oracle and can force rebalances through uniswap
 */
contract UniswapDCABridge is BiDCABridge {
    using SafeERC20 for IERC20;

    address internal constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;

    uint160 internal constant SQRT_PRICE_LIMIT_X96 = 1461446703485210103287273052203988822378723970341;
    ISwapRouter public constant UNI_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);

    uint256 public constant MAX_AGE = 1 days; // Heartbeat of oracle is 24 hours.
    uint256 public constant SLIPPAGE = 100; // Basis points

    IChainlinkOracle public immutable ORACLE;

    constructor(
        address _rollupProcessor,
        address _assetA,
        address _assetB,
        uint256 _tickSize,
        address _oracle
    ) BiDCABridge(_rollupProcessor, DAI, address(WETH), _tickSize) {
        ORACLE = IChainlinkOracle(_oracle);

        IERC20(_assetA).safeApprove(address(UNI_ROUTER), type(uint256).max);
        IERC20(_assetB).safeApprove(address(UNI_ROUTER), type(uint256).max);
    }

    /**
     * @notice Rebalances within ticks, then across ticks, and finally, take the remaining funds to uniswap
     * where it is traded for the opposite, and used to rebalance completely
     * @dev Uses a specific path for the assets to do the swap
     * @dev Slippage protection through the chainlink oracle, as a base price
     * @dev Can be quite gas intensive as it will loop multiple times over the ticks to fill orders.
     * @return aFlow The flow of token A
     * @return bFlow The flow of token B
     */
    function rebalanceAndFillUniswap() external returns (int256, int256) {
        uint256 oraclePrice = getPrice();
        (int256 aFlow, int256 bFlow, uint256 a, uint256 b) = _rebalanceAndFill(0, 0, oraclePrice, true);

        if (a > 0 && b > 0) {
            (aFlow, bFlow, a, b) = _rebalanceAndFill(a, b, oraclePrice, true);
        }

        if (a > 0) {
            // Trade all A to B using uniswap. Then compute the price using output of that price, rounding DOWN as the price passed rebalance. Rounding DOWN ensures that B received / price >= A available
            uint256 bOffer = UNI_ROUTER.exactInput(
                ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(ASSET_A, uint24(100), USDC, uint24(500), ASSET_B),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: a,
                    amountOutMinimum: (denominateAssetAInB(a, oraclePrice, false) * (10000 - SLIPPAGE)) / 10000
                })
            );

            uint256 price = (bOffer * 1e18) / a;

            (aFlow, bFlow, , ) = _rebalanceAndFill(0, bOffer, price, true);
        }

        if (b > 0) {
            // Trade all B to A using uniswap. Then compute the price using output of that price, rounding UP as the price passed rebalance. Rounding UP to ensure that A received * price >= B available
            uint256 aOffer = UNI_ROUTER.exactInput(
                ISwapRouter.ExactInputParams({
                    path: abi.encodePacked(ASSET_B, uint24(500), USDC, uint24(100), ASSET_A),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: b,
                    amountOutMinimum: (denominateAssetBInA(b, oraclePrice, false) * (10000 - SLIPPAGE)) / 10000
                })
            );

            uint256 price = (b * 1e18 + aOffer - 1) / aOffer;

            (aFlow, bFlow, , ) = _rebalanceAndFill(aOffer, 0, price, true);
        }

        return (aFlow, bFlow);
    }

    /**
     * @notice Fetch the price from the chainlink oracle.
     * @dev Reverts if the price is stale or negative
     * @return Price
     */
    function getPrice() public virtual override(BiDCABridge) returns (uint256) {
        (, int256 answer, , uint256 updatedAt, ) = ORACLE.latestRoundData();
        if (updatedAt + MAX_AGE < block.timestamp) {
            revert("Too old");
        }

        if (answer < 0) {
            revert("Negative price");
        }

        return uint256(answer);
    }
}
