// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;
pragma experimental ABIEncoderV2;
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {Vm} from "../../../../lib/forge-std/src/Vm.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {INonfungiblePositionManager} from "../../../interfaces/uniswapv3/INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "../../../interfaces/uniswapv3/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "../../../interfaces/uniswapv3/IUniswapV3Pool.sol";
import {TickMath} from "../../../libraries/uniswapv3/TickMath.sol";
import {UniRangeOrderBridge} from "../../../bridges/uniswap_lp/UniRangeOrderBridge.sol";
import {TransferHelper, ISwapRouter} from "../../../bridges/uniswap_lp/ParentUniLPBridge.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {LiquidityAmounts} from "../../../libraries/uniswapv3/LiquidityAmounts.sol";
import {AztecKeeper} from "../../../bridges/uniswap_lp/AztecKeeper.sol";

contract UniRange is BridgeTestBase {
    address private constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address private constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address private constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address private constant FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address private constant ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant NONFUNGIBLE_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address private constant QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address private pool = 0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36;
    address[] private tokens = [USDT, DAI, WETH, USDC, WBTC];
    //                                  1           2              3            4           5               6           7               8

    address[][] private pairs = [[USDT, WETH], [WETH, USDC], [USDT, WBTC], [WETH, WBTC], [USDC, WBTC]];
    //                              1      2    3       4   5       6   7     8
    uint256[] private poolFees = [500, 3000, 3000, 3000, 3000, 100, 3000, 3000];
    uint16 private poolFee;

    UniRangeOrderBridge private asyncBridge;

    uint256 private id;

    error NotInTickRange();

    function setUp() public {
        asyncBridge = new UniRangeOrderBridge(address(ROLLUP_PROCESSOR));

        vm.label(FACTORY, "FACTORY");
        vm.label(ROUTER, "ROUTER");
        vm.label(NONFUNGIBLE_POSITION_MANAGER, "MANAGER");
        vm.label(address(DAI), "DAI");
        vm.label(address(WETH), "WETH");
        vm.label(address(USDC), "USDC");
        vm.label(address(asyncBridge), "ASYNCBRIDGE");

        vm.deal(address(asyncBridge), uint256(10000));
        vm.deal(address(this), uint256(10000));

        vm.startPrank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(asyncBridge), 200000000);
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        for (uint256 i = 0; i < tokens.length; i++) {
            if (!isSupportedAsset(tokens[i])) {
                ROLLUP_PROCESSOR.setSupportedAsset(tokens[i], 100000);
            }
        }

        vm.stopPrank();
    }

    function testAsyncLimitOrder(uint256 _deposit) public {
        for (uint256 i = 0; i < pairs.length - 4; i++) {
            poolFee = uint16(poolFees[i]);
            pool = IUniswapV3Factory(FACTORY).getPool(pairs[i][0], pairs[i][1], uint24(poolFee));
            (uint160 originalPrice, , , , , , ) = IUniswapV3Pool(pool).slot0();
            address token0 = pairs[i][0] < pairs[i][1] ? pairs[i][0] : pairs[i][1];
            address token1 = pairs[i][0] < pairs[i][1] ? pairs[i][1] : pairs[i][0];
            bool token0HighPrice = _token0Price(originalPrice, 40, token0, token1) > 0;
            (uint256 lower, uint256 higher) = _limitsOfPool(pool, token0HighPrice ? token1 : token0);
            _deposit = bound(_deposit, lower, higher);
            _testAsyncLimitOrder(_deposit, pairs[i][0], pairs[i][1]);
        }
    }

    function testAsyncLimitOrderThenCancel(uint256 _deposit) public {
        for (uint256 i = 0; i < pairs.length - 4; i++) {
            poolFee = uint16(poolFees[i]);
            pool = IUniswapV3Factory(FACTORY).getPool(pairs[i][0], pairs[i][1], uint24(poolFee));
            (uint160 originalPrice, , , , , , ) = IUniswapV3Pool(pool).slot0();
            address token0 = pairs[i][0] < pairs[i][1] ? pairs[i][0] : pairs[i][1];
            address token1 = pairs[i][0] < pairs[i][1] ? pairs[i][1] : pairs[i][0];
            bool token0HighPrice = _token0Price(originalPrice, 40, token0, token1) > 0;
            (uint256 lower, uint256 higher) = _limitsOfPool(pool, token0HighPrice ? token1 : token0);
            _deposit = bound(_deposit, lower, higher);
            _testAsyncLimitOrderThenCancel(_deposit, pairs[i][0], pairs[i][1]);
        }
    }

    function _testAsyncLimitOrderThenCancel(
        uint256 _deposit,
        address _tokenA,
        address _tokenB
    ) internal {
        uint64 data = _packData(uint160(50));

        //this isnt working because we called it directly from the bridge but we need the
        //rollup processor to record the interactionnonce since we prodd the rollup to call finalise

        {
            //BEGIN SCOPE
            address inToken;
            address outToken;
            (uint160 originalPrice, , , , , , ) = IUniswapV3Pool(pool).slot0();
            if (
                _token0Price(
                    originalPrice,
                    40,
                    _tokenA < _tokenB ? _tokenA : _tokenB,
                    _tokenA < _tokenB ? _tokenB : _tokenA
                ) > 0
            ) {
                inToken = _tokenA;
                outToken = _tokenB;
            } else {
                inToken = _tokenB;
                outToken = _tokenA;
            }
            deal(inToken, address(asyncBridge), _deposit);
            //vm.startPrank(address(ROLLUP_PROCESSOR));

            uint256 bridgeId = encodeBridgeCallData(
                id,
                getRealAztecAsset(inToken),
                emptyAsset,
                getRealAztecAsset(outToken),
                getRealAztecAsset(inToken),
                data
            );

            //vm.expectEmit(true, true, false, true);

            //adjust this
            emit DefiBridgeProcessed(bridgeId, getNextNonce(), 1, 0, 0, true, "");

            sendDefiRollup(bridgeId, _deposit);

            //vm.stopPrank();
            //END OF SCOPE
        }
        (, , uint256 amount0, uint256 amount1, , , , , ) = asyncBridge.getDeposit(1);

        (uint256 out0, uint256 out1) = asyncBridge.cancel(1);
        //ROLLUP_PROCESSOR.processAsyncDefiInteraction(0);
        vm.startPrank(address(ROLLUP_PROCESSOR));
        asyncBridge.finalise(
            emptyAsset,
            emptyAsset,
            getRealAztecAsset(address(_tokenA)),
            getRealAztecAsset(address(_tokenB)),
            uint256(1),
            uint64(0)
        );
        vm.stopPrank();
        //one of the outputs will always be 0, we will onyl need to test the non zero one

        assertTrue(
            (out0 == 0 ? out1 : out0) >= ((amount0 == 0 ? amount1 : amount0) * 99999) / 100000,
            "failed .000001 margin"
        );
    }

    function _testAsyncLimitOrder(
        uint256 _deposit,
        address _tokenA,
        address _tokenB
    ) internal {
        uint64 data = _packData(uint160(80));

        address inToken;
        address outToken;

        if (true) {
            (uint160 originalPrice, , , , , , ) = IUniswapV3Pool(pool).slot0();
            //we will be executing a buy limit order
            //a buy limit order requires that the lower price asset be provided. then wwhen the price decreases
            //and we remove liquidity, we will receive the higher price asset
            //since solidity is integer only if token0Price is for example .005 eth it will be 0.
            //so to find out which is higher priced we need to check if token0Price > 0.
            //if yes then token0 is higher priced. so we use token1.
            //if no then token0 is lower priced. so we use token0.
            if (
                _token0Price(
                    originalPrice,
                    40,
                    _tokenA < _tokenB ? _tokenA : _tokenB,
                    _tokenA < _tokenB ? _tokenB : _tokenA
                ) > 0
            ) {
                inToken = _tokenA;
                outToken = _tokenB;
            } else {
                inToken = _tokenB;
                outToken = _tokenA;
            }
            deal(inToken, address(asyncBridge), _deposit);
            vm.startPrank(address(ROLLUP_PROCESSOR));
            asyncBridge.convert(
                getRealAztecAsset(inToken),
                emptyAsset,
                getRealAztecAsset(outToken),
                getRealAztecAsset(inToken),
                _deposit,
                1,
                data,
                address(0)
            );

            vm.stopPrank();
            _lowerPriceToTickRange(outToken, inToken);
        }
        if (false) {
            uint256 bridgeId = encodeBridgeCallData(
                id,
                getRealAztecAsset(address(_tokenA)),
                emptyAsset,
                getRealAztecAsset(address(_tokenB)),
                getRealAztecAsset(address(_tokenA)),
                data
            );

            vm.expectEmit(true, true, false, true);

            //adjust this
            emit DefiBridgeProcessed(bridgeId, getNextNonce(), 1, 0, 0, true, "");

            sendDefiRollup(bridgeId, _deposit);
        }

        (, , uint256 amount0, uint256 amount1, , , , , ) = asyncBridge.getDeposit(1);
        (uint256 out0, uint256 out1) = asyncBridge.trigger(1);
        vm.startPrank(address(ROLLUP_PROCESSOR));
        asyncBridge.finalise(
            emptyAsset,
            emptyAsset,
            getRealAztecAsset(address(_tokenB)),
            getRealAztecAsset(address(_tokenA)),
            1,
            data
        );
        vm.stopPrank();

        //ROLLUP_PROCESSOR.processAsyncDefiInteraction(1);

        {
            if (amount1 > 0) {
                assertTrue(out1 < amount1);
                assertTrue(out1 > 0 && out0 > 0);
            } else {
                assertTrue(out1 > 0 && out0 > 0);
            }
        }
    }

    function _marginOfError(
        uint256 _amount0,
        uint256 _redeem0,
        uint256 _amount1,
        uint256 _redeem1,
        uint256 _marginFrac
    ) internal {
        //tests for rounding error

        //necessary when testing smaller values, which have larger margin % but are smaller in absolute terms
        //e.g. 1000 wei -> 999 wei, which is .1% error, very high

        //we dont care if the amount redeemed is more than the amount minted, only less than

        uint256 scale = 1000000;

        //sometimes when 1 output is much less than the input , the other output is much larger than its original input
        //e.g. token0 input of 100, output of 99, but token1 input of 100 and output of 101

        uint256 sum = ((_redeem0 * scale) / _amount0) + ((_redeem1 * scale) / _amount1);

        assertTrue(sum >= (2 * scale) - scale / _marginFrac, "not within %margin");
    }

    function _packData(uint160 _priceDiff) internal returns (uint64 data) {
        //we need to do these checks because token0Price is not always the higher priced asset as
        //explained elsewhere. If DAI is token1 and ETH is token0, then using slot0 sqrtPriceX96
        //is acceptable. However if say USDC is token0 and ETH is token1, then slot0 sqrtPriceX96
        //when converted to token0Price is USDC's price, which is the lower priced asset.
        //so then if we multiply USDC's price by 80% , decreasing it, we are actually increasing ETH's price!!
        //ex: token0Price = USDC price = ratio ETH / USDC. decreasing this means USDC denominator, increasing ETH price
        //so then their will be errors, as you are actually specifying that your range order will be
        //executed when the ETH price increases, which isn't what you wanted nor what you attempted.

        (uint160 price, int24 currentTick, , , , , ) = IUniswapV3Pool(pool).slot0();
        int24 _a;
        int24 _b;
        address token0 = IUniswapV3Pool(pool).token0();
        address token1 = IUniswapV3Pool(pool).token1();
        uint256 token0Price = _token0Price(price, 20, token0, token1);
        if (token0Price > 0) {
            price = (price * _priceDiff) / 100;
            currentTick = TickMath.getTickAtSqrtRatio(price); //get new target tick
            (_a, _b) = _adjustTickParams(currentTick - IUniswapV3Pool(pool).tickSpacing(), currentTick, pool);
        } else {
            // since 'price' is price of lower priced asset, we need to increase it to decrease high price asset's price
            price = (price * (200 - _priceDiff)) / 100;
            currentTick = TickMath.getTickAtSqrtRatio(price); //get new target tick
            (_a, _b) = _adjustTickParams(currentTick, currentTick + IUniswapV3Pool(pool).tickSpacing(), pool);
        }

        uint24 a = uint24(_a);
        uint24 b = uint24(_b);
        uint48 ticks = (uint48(a) << 24) | uint48(b);
        uint8 fee = uint8(poolFee / 100);
        uint8 daysToCancel = 0;
        uint16 last16 = ((uint16(fee) << 8) | uint16(daysToCancel));
        data = (uint64(ticks) << 16) | uint64(last16);
    }

    function _lowerPriceToTickRange(address _tokenIn, address _tokenOut) internal {
        (, , , , int24 tickLower, int24 tickUpper, , , ) = asyncBridge.getDeposit(1);
        {
            ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: _tokenIn,
                tokenOut: _tokenOut,
                fee: uint24(poolFee),
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: IERC20(_tokenIn).totalSupply() / 10000,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });

            (uint160 newPrice, , , , , , ) = IUniswapV3Pool(pool).slot0();
            //if price / token0Price is the price of higher priced asset, then flag is true. else false.
            //see packData for description of why this is necessary.
            //tokenIn is the higher priced token.
            //if tokenIn token0, then flag is true.
            bool flag = _tokenIn < _tokenOut;
            int24 whichTick = flag ? tickUpper : tickLower;
            //token0Price = higher priced asset case -> newTick >= tickLower
            //lower price until it reaches tickLower
            //token0Price = lower priced asset case ->
            //we want to increase token0Price until it reaches tickLower
            //    tickUpper    1200 < 1500 newPrice while this is TRUE swap
            //    tickLower    1/1200 <  1/1500 newPrice while this is FALSE swap
            //we swap in smaller increments to ensure we meet the range and don't over shoot it
            while ((TickMath.getTickAtSqrtRatio(newPrice) >= whichTick) == flag) {
                deal(_tokenIn, address(this), IERC20(_tokenIn).totalSupply() / 10000);
                TransferHelper.safeApprove(_tokenIn, ROUTER, IERC20(_tokenIn).totalSupply() / 10000);
                ISwapRouter(ROUTER).exactInputSingle(swapParams);
                (newPrice, , , , , , ) = IUniswapV3Pool(pool).slot0();
            }
            //we ensure the price of the pool meets the target range of our order
            //this is important as otherwise the range order will not execute
            if (
                !(TickMath.getTickAtSqrtRatio(newPrice) <= tickUpper &&
                    TickMath.getTickAtSqrtRatio(newPrice) >= tickLower)
            ) revert NotInTickRange();
        }
    }

    function _adjustTickParams(
        int24 _tickLower,
        int24 _tickUpper,
        address _pool
    ) internal returns (int24 newTickLower, int24 newTickUpper) {
        //adjust the params s.t. they conform to tick spacing and do not fail the tick % tickSpacing == 0 check
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        newTickLower = _tickLower % pool.tickSpacing() == 0
            ? _tickLower
            : _tickLower - (_tickLower % pool.tickSpacing());
        newTickUpper = _tickUpper % pool.tickSpacing() == 0
            ? _tickUpper
            : _tickUpper - (_tickUpper % pool.tickSpacing());
    }

    function _token0Price(
        uint160 _sqrtPriceX96,
        uint256 _x,
        address _token0,
        address _token1
    ) internal returns (uint256) {
        address token0 = _token0 < _token1 ? _token0 : _token1;
        address token1 = _token0 < _token1 ? _token1 : _token0;
        uint256 scalar = (10**IERC20Metadata(token0).decimals()) / (10**IERC20Metadata(token1).decimals());
        return (scalar * (_sqrtPriceX96 / (2**_x))**2) / (2**(192 - (2 * _x)));
    }

    function _limitsOfPool(address _pool, address _token) internal returns (uint256, uint256) {
        //there are max liquidity constraints per pool, therefore it makes sense to define custom limits
        //on a per pool basis rather than a per token basis alone.
        //USDT WETH 500
        if (_pool == 0x11b815efB8f581194ae79006d24E0d814B7697F6) {
            if (_token == USDT) return (1000000000000, 18479553865698585296224760);
            else if (_token == WETH) return (16990826690438413, 218809284046322613163859525526366);
        }
        //WETH USDC 3000
        else if (_pool == 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8) {
            if (_token == WETH) return (16990826690438413, 218809284046322613163859525526366);
            else if (_token == USDC) return (1000000000000, 10659313385221375029114507794201510);
        }
        //USDT WBTC 3000
        else if (_pool == 0x9Db9e0e53058C89e5B94e29621a205198648425B) {
            if (_token == USDT) return (10000000, 26567527292104433082061);
            else if (_token == WBTC) return (10000, 16990826690438413);
        }
        //WETH WBTC 3000
        else if (_pool == 0xCBCdF9626bC03E24f779434178A73a0B4bad62eD) {
            if (_token == WETH) return (1699082669043840, 2188092840463226131638595111);
            else if (_token == WBTC) return (100000, 2790826690438412);
        }
        //USDC WBTC 3000
        else if (_pool == 0x99ac8cA7087fA4A2A1FB6357269965A2014ABc35) {
            if (_token == USDC) return (1000000, 10659313385221300);
            else if (_token == WBTC) return (100000, 16990826690438413);
        }
    }
}
