// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;
pragma experimental ABIEncoderV2;
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";
import {Vm} from "../../../../lib/forge-std/src/Vm.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {INonfungiblePositionManager} from "../../../interfaces/uniswapv3/INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "../../../interfaces/uniswapv3/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "../../../interfaces/uniswapv3/IUniswapV3Pool.sol";
import {IQuoterV2} from "../../../interfaces/uniswapv3/IQuoterV2.sol";
import {TickMath} from "../../../libraries/uniswapv3/TickMath.sol";
import {FullMath} from "../../../libraries/uniswapv3/FullMath.sol";
import {UniLPBridge} from "../../../bridges/uniswap_lp/UniLPBridge.sol";
import {TransferHelper, ISwapRouter, ParentUniLPBridge} from "../../../bridges/uniswap_lp/ParentUniLPBridge.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {LiquidityAmounts} from "../../../libraries/uniswapv3/LiquidityAmounts.sol";

contract UniswapLPTest is BridgeTestBase {
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
    UniLPBridge private syncBridge;
    uint256 private id;

    function setUp() public {
        vm.label(FACTORY, "FACTORY");
        vm.label(ROUTER, "ROUTER");
        vm.label(NONFUNGIBLE_POSITION_MANAGER, "MANAGER");
        vm.label(address(USDT), "USDT");
        vm.label(address(WETH), "WETH");
        vm.label(address(USDC), "USDC");

        syncBridge = new UniLPBridge(address(ROLLUP_PROCESSOR));
        vm.label(address(syncBridge), "SYNCBRIDGE");
        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(syncBridge), 20000000000000000000);
        vm.deal(address(this), 20000000000);
        vm.deal(address(ROLLUP_PROCESSOR), 20000000000);
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        for (uint256 i = 0; i < tokens.length; i++) {
            if (!isSupportedAsset(tokens[i])) {
                vm.prank(MULTI_SIG);
                ROLLUP_PROCESSOR.setSupportedAsset(tokens[i], 20000000000000000000);
            }
        }

        vm.deal(address(syncBridge), uint256(10000));
        vm.deal(address(this), uint256(10000));
    }

    //both testTwoPartMint and testMintBySwap are set to only try 2 pairs right now
    //because otherwise testing takes too long (5-7 min to do both tests)
    function testTwoPartMint(uint256 _deposit, uint256 _ethDeposit) public {
        for (uint256 i = 0; i < pairs.length - 4; i++) {
            poolFee = uint16(poolFees[i]);
            address token0 = pairs[i][0] < pairs[i][1] ? pairs[i][0] : pairs[i][1];
            address token1 = pairs[i][0] < pairs[i][1] ? pairs[i][1] : pairs[i][0];
            _testTwoPartMint(_deposit, _ethDeposit, token0, token1);
        }
    }

    function testMintBySwap(uint256 _deposit) public {
        for (uint256 i = 0; i < pairs.length - 4; i++) {
            poolFee = uint16(poolFees[i]);
            pool = IUniswapV3Factory(FACTORY).getPool(pairs[i][0], pairs[i][1], uint24(poolFee));
            address token0 = pairs[i][0] < pairs[i][1] ? pairs[i][0] : pairs[i][1];
            address token1 = pairs[i][0] < pairs[i][1] ? pairs[i][1] : pairs[i][0];
            _testMintBySwap(_deposit, token0, token1);
            if (token0 == WETH) {
                _testMintBySwap(_deposit, address(0), token1);
            }
        }
    }

    //INTERACTIONS
    //INTERACTION TYPE 1 MINT PART 1
    //1 real (token A) 1 not used
    //1 virtual 1 not used
    //INTERACTION TYPE 2 MINT PART 2
    //1 real (tokenB) 1 virtual (tokenA virtualnote)
    //1 virtual 1 real (refund) (tokenA or tokenB)
    //INTERACTION TYPE 3 MINT BY SWAP
    //1 real (tokenA) 1 not used
    //1 virtual 1 real (tokenB)
    //INTERACTION TYPE 4 LP REDEMPTION
    //1 virtual 1 not used (LP virtualnote)
    //1 real 1 real (tokenA, tokenB)
    //expect revert test cases:
    //case 1 : specify incorrect refund on interaction 2
    //case 2: invalid outputs for liquidity position redemption / interaction 4
    function testExpectReverts(uint256 _amount0, uint256 _amount1) public {
        for (uint256 i = 0; i < pairs.length - 4; i++) {
            poolFee = uint16(poolFees[i]);
            pool = IUniswapV3Factory(FACTORY).getPool(pairs[i][0], pairs[i][1], uint24(poolFee));
            address token0 = pairs[i][0] < pairs[i][1] ? pairs[i][0] : pairs[i][1];
            address token1 = pairs[i][0] < pairs[i][1] ? pairs[i][1] : pairs[i][0];
            _testExpectRevertInvalidRefund(_amount0, _amount1, token0, token1);
            _testExpectRevertInvalidOutputs(_amount0, _amount1, token0, token1);
            _testExpectRevertInvalidCaller(_amount0, _amount1, token0, token1);
        }
    }

    function _testExpectRevertInvalidRefund(
        uint256 _amount0,
        uint256 _amount1,
        address _token0,
        address _token1
    ) internal {
        //most of these upper limits are as a result of the pools limited liquidity
        //we constrain ETH to 1 trillion ETH, fairly reasonable IMO
        pool = IUniswapV3Factory(FACTORY).getPool(_token0, _token1, uint24(poolFee));
        {
            (uint256 lower0, uint256 higher0, uint256 lower1, uint256 higher1) = _limitsOfPool(pool);
            _amount0 = bound(_amount0, lower0, higher0);
            _amount1 = bound(_amount1, lower1, higher1);
        }

        deal(_token1, address(syncBridge), _amount1);
        deal(_token0, address(syncBridge), _amount0);

        uint256 virtualNoteAmount;

        vm.startPrank(address(ROLLUP_PROCESSOR));

        {
            (uint256 outputValueA, , ) = syncBridge.convert(
                getRealAztecAsset(_token1),
                emptyAsset,
                AztecTypes.AztecAsset({id: 1, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL}),
                emptyAsset,
                _amount1,
                1,
                0,
                address(0)
            );

            vm.stopPrank();

            uint256 bridgeToken1Qty = IERC20(_token1).balanceOf(address(syncBridge));
            virtualNoteAmount = outputValueA;
            assertEq(_amount1, bridgeToken1Qty, "Balances must match ; first convert call");
        }

        {
            uint64 data;
            (uint160 price, , , , , , ) = IUniswapV3Pool(pool).slot0();

            {
                (int24 _a, int24 _b) = _adjustTickParams(
                    TickMath.getTickAtSqrtRatio((price * 60) / 100),
                    TickMath.getTickAtSqrtRatio((price * 120) / 100),
                    pool
                );
                uint24 a = uint24(_a);
                uint24 b = uint24(_b);
                uint48 ticks = (uint48(a) << 24) | uint48(b);
                uint16 fee = uint16(IUniswapV3Pool(pool).fee());
                data = (uint64(ticks) << 16) | uint64(fee);
            }

            vm.startPrank(address(ROLLUP_PROCESSOR));
            //third argument should be token0 or token1 not 0
            vm.expectRevert(abi.encodeWithSelector(UniLPBridge.InvalidRefund.selector));
            syncBridge.convert(
                AztecTypes.AztecAsset({id: 2, erc20Address: _token0, assetType: AztecTypes.AztecAssetType.ERC20}),
                AztecTypes.AztecAsset({id: 1, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL}),
                AztecTypes.AztecAsset({id: 2, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL}),
                AztecTypes.AztecAsset({id: 2, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.ERC20}),
                _amount0,
                2,
                data,
                address(0)
            );

            vm.stopPrank();
        }
    }

    function _testExpectRevertInvalidCaller(
        uint256 _amount0,
        uint256 _amount1,
        address _token0,
        address _token1
    ) internal {
        pool = IUniswapV3Factory(FACTORY).getPool(_token0, _token1, uint24(poolFee));
        {
            (uint256 lower0, uint256 higher0, uint256 lower1, uint256 higher1) = _limitsOfPool(pool);
            _amount0 = bound(_amount0, lower0, higher0);
            _amount1 = bound(_amount1, lower1, higher1);
        }

        vm.expectRevert(abi.encodeWithSelector(ErrorLib.InvalidCaller.selector));

        syncBridge.convert(
            AztecTypes.AztecAsset({id: 1, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL}),
            emptyAsset,
            AztecTypes.AztecAsset({id: 1, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL}),
            emptyAsset,
            _amount1,
            1,
            0,
            address(0)
        );
    }

    function _testExpectRevertInvalidOutputs(
        uint256 _amount0,
        uint256 _amount1,
        address _token0,
        address _token1
    ) internal {
        pool = IUniswapV3Factory(FACTORY).getPool(_token0, _token1, uint24(poolFee));

        {
            (uint256 lower0, uint256 higher0, uint256 lower1, uint256 higher1) = _limitsOfPool(pool);
            _amount0 = bound(_amount0, lower0, higher0);
            _amount1 = bound(_amount1, lower1, higher1);
        }

        deal(_token1, address(syncBridge), _amount1);
        deal(_token0, address(syncBridge), _amount0);

        uint256 virtualNoteAmount;

        vm.startPrank(address(ROLLUP_PROCESSOR));

        {
            (uint256 outputValueA, , ) = syncBridge.convert(
                getRealAztecAsset(_token1),
                emptyAsset,
                AztecTypes.AztecAsset({id: 1, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL}),
                emptyAsset,
                _amount1,
                1,
                0,
                address(0)
            );

            vm.stopPrank();

            uint256 bridgeToken1Qty = IERC20(_token1).balanceOf(address(syncBridge));
            virtualNoteAmount = outputValueA;
            assertEq(_amount1, bridgeToken1Qty, "Balances must match ; first convert call");
        }

        {
            uint64 data;
            (uint160 price, , , , , , ) = IUniswapV3Pool(pool).slot0();

            {
                (int24 _a, int24 _b) = _adjustTickParams(
                    TickMath.getTickAtSqrtRatio((price * 60) / 100),
                    TickMath.getTickAtSqrtRatio((price * 120) / 100),
                    pool
                );
                uint24 a = uint24(_a);
                uint24 b = uint24(_b);
                uint48 ticks = (uint48(a) << 24) | uint48(b);
                uint16 fee = uint16(IUniswapV3Pool(pool).fee());
                data = (uint64(ticks) << 16) | uint64(fee);
            }

            vm.startPrank(address(ROLLUP_PROCESSOR));
            (uint256 callTwoOutputValueA, , ) = syncBridge.convert(
                AztecTypes.AztecAsset({id: 2, erc20Address: _token0, assetType: AztecTypes.AztecAssetType.ERC20}),
                AztecTypes.AztecAsset({id: 1, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL}),
                AztecTypes.AztecAsset({id: 2, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL}),
                AztecTypes.AztecAsset({id: 2, erc20Address: _token0, assetType: AztecTypes.AztecAssetType.ERC20}),
                _amount0,
                2,
                data,
                address(0)
            );

            vm.stopPrank();

            uint256 callTwoVirtualNoteAmount = callTwoOutputValueA;

            (, , uint256 amount0, uint256 amount1, , , , , ) = syncBridge.getDeposit(2);
            vm.startPrank(address(ROLLUP_PROCESSOR));
            vm.expectRevert(abi.encodeWithSelector(ParentUniLPBridge.InvalidOutputs.selector));

            syncBridge.convert(
                AztecTypes.AztecAsset({id: 3, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL}),
                AztecTypes.AztecAsset({id: 1, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.NOT_USED}),
                AztecTypes.AztecAsset({id: 2, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.ERC20}),
                AztecTypes.AztecAsset({id: 2, erc20Address: _token0, assetType: AztecTypes.AztecAssetType.ERC20}),
                callTwoVirtualNoteAmount,
                3,
                0,
                address(0)
            );
            vm.stopPrank();
        }
    }

    function _testTwoPartMint(
        uint256 _amount0,
        uint256 _amount1,
        address _token0,
        address _token1
    ) internal {
        pool = IUniswapV3Factory(FACTORY).getPool(_token0, _token1, uint24(poolFee));
        {
            (uint256 lower0, uint256 higher0, uint256 lower1, uint256 higher1) = _limitsOfPool(pool);
            _amount0 = bound(_amount0, lower0, higher0);
            _amount1 = bound(_amount1, lower1, higher1);
        }

        //give our bridge token qties so it can swap and change pool price
        deal(_token0, address(this), _amount0);
        deal(_token1, address(this), _amount1);
        if (true) {
            (uint160 originalPrice, , , , , , ) = IUniswapV3Pool(pool).slot0();
            UniLPBridge.OptimalLiqParams memory liqParams = UniLPBridge.OptimalLiqParams({
                token0: _token0,
                token1: _token1,
                fee: IUniswapV3Pool(pool).fee(),
                amount0: _amount0,
                amount1: _amount1,
                sqrtRatioAX96: (originalPrice * 60) / 100,
                sqrtRatioBX96: originalPrice * 2
            });
            (_amount0, _amount1) = syncBridge.optimizeLiquidity(liqParams);
            bool flag = IERC20(_token0).balanceOf(address(this)) > _amount0;
            address tokenIn = flag ? _token0 : _token1;
            address tokenOut = flag ? _token1 : _token0;
            uint256 amountIn = flag
                ? IERC20(_token0).balanceOf(address(this)) - _amount0
                : IERC20(_token1).balanceOf(address(this)) - _amount1;
            if (amountIn > 0) {
                TransferHelper.safeApprove(tokenIn, ROUTER, 0);
                TransferHelper.safeApprove(tokenIn, ROUTER, amountIn);
                ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: IUniswapV3Pool(pool).fee(),
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum: 0,
                    sqrtPriceLimitX96: tokenIn < tokenOut ? (originalPrice * 60) / 100 : (originalPrice * 120) / 100
                });

                ISwapRouter(ROUTER).exactInputSingle(params);
                TransferHelper.safeApprove(tokenIn, ROUTER, 0);
            }
        }
        //(_amount0, _amount1) = _optimizeLiquidity(_amount1, _amount0);
        deal(_token1, address(ROLLUP_PROCESSOR), _amount1);
        deal(_token0, address(ROLLUP_PROCESSOR), _amount0);
        //deal(_token1, address(syncBridge), _amount1);
        //deal(_token0, address(syncBridge), _amount0);
        (uint160 originalPrice, , , , , , ) = IUniswapV3Pool(pool).slot0();

        uint256 virtualNoteAmount;

        //vm.startPrank(address(ROLLUP_PROCESSOR));
        uint256 mostRecentNonce = getNextNonce();
        {
            (uint256 outputValueA, , ) = _convert(
                getRealAztecAsset(_token1),
                emptyAsset,
                AztecTypes.AztecAsset({
                    id: getNextNonce(),
                    erc20Address: address(0),
                    assetType: AztecTypes.AztecAssetType.VIRTUAL
                }),
                emptyAsset,
                _amount1,
                0
            );

            //vm.stopPrank();
            uint256 bridgeToken1Qty = IERC20(_token1).balanceOf(address(syncBridge));
            virtualNoteAmount = outputValueA;
            assertEq(_amount1, bridgeToken1Qty, "Balances must match ; first convert call");
        }

        {
            uint64 data;

            {
                (uint160 price, , , , , , ) = IUniswapV3Pool(pool).slot0();

                (int24 _a, int24 _b) = _adjustTickParams(
                    TickMath.getTickAtSqrtRatio((price * 60) / 100),
                    TickMath.getTickAtSqrtRatio((price * 120) / 100),
                    pool
                );
                uint24 a = uint24(_a);
                uint24 b = uint24(_b);
                uint48 ticks = (uint48(a) << 24) | uint48(b);
                uint16 fee = uint16(IUniswapV3Pool(pool).fee());
                data = (uint64(ticks) << 16) | uint64(fee);
            }

            //vm.startPrank(address(ROLLUP_PROCESSOR));
            uint256 newestNonce = getNextNonce();
            (uint256 callTwoOutputValueA, , ) = _convert(
                getRealAztecAsset(_token0),
                AztecTypes.AztecAsset({
                    id: mostRecentNonce,
                    erc20Address: address(0),
                    assetType: AztecTypes.AztecAssetType.VIRTUAL
                }),
                AztecTypes.AztecAsset({
                    id: getNextNonce(),
                    erc20Address: address(0),
                    assetType: AztecTypes.AztecAssetType.VIRTUAL
                }),
                getRealAztecAsset(_token0),
                _amount0,
                data
            );

            //vm.stopPrank();

            (, , uint256 amount0, uint256 amount1, , , , , ) = syncBridge.getDeposit(newestNonce);

            (uint256 redeem0, uint256 redeem1) = _redeem(callTwoOutputValueA, newestNonce, _token0, _token1);

            {
                //sqrt(10^b-a * token0Price) * 2**96
                originalPrice = originalPrice / (2**48); //sqrt(10^b-a * token0Price) * 2**48
                originalPrice = originalPrice**2; //10^b-a * token0Price * 2**96

                //convert amount0 to usdt value / qty
                //sum converted amount with amount1 usdt qty
                uint256 total1ValueBefore = amount1 + ((amount0 * originalPrice) / 2**96);
                //convert redeem0 to usdt value qty
                //sum converted redeemed amount with redeem1 usdt qty
                uint256 total1ValueAfter = redeem1 + ((redeem0 * originalPrice) / 2**96);
                //convert amount1 to eth equivalent qty / value
                //sum converted amount1 eth value with amount0 eth value for total eth value
                uint256 total0ValueBefore = amount0 + ((amount1 * (2**96)) / originalPrice);
                //convert redeem1 to equivalent eth value
                //sum converted redeem1 equivalent eth value with redeem0 eth value for total eth value
                uint256 total0ValueAfter = redeem0 + ((redeem1 * (2**96)) / originalPrice);
                assertTrue(
                    (total0ValueBefore * 95) / 100 <= total0ValueAfter ||
                        (total1ValueBefore * 95) / 100 <= total1ValueAfter,
                    "Equivalent values in either token did not match upon redemption"
                );
            }
        }
    }

    function _testMintBySwap(
        uint256 _deposit,
        address _token0,
        address _token1
    ) internal {
        {
            (uint256 lower, uint256 higher) = _limitsOfPoolSwap(pool, _token0 == address(0) ? WETH : _token0);
            _deposit = bound(_deposit, lower, higher);
        }

        //0 address represents ETH
        if (_token0 == address(0)) {
            deal(address(ROLLUP_PROCESSOR), _deposit);
        } else {
            deal(_token0, address(ROLLUP_PROCESSOR), _deposit);
        }

        uint64 data;
        //pack params into data

        {
            (int24 _a, int24 _b) = _adjustTickParams(TickMath.MIN_TICK, TickMath.MAX_TICK, pool);
            uint24 a = uint24(_a);
            uint24 b = uint24(_b);
            uint48 ticks = (uint48(a) << 24) | uint48(b);
            uint16 fee = poolFee;
            data = (uint64(ticks) << 16) | uint64(fee);
        }

        //vm.startPrank(address(ROLLUP_PROCESSOR));
        uint256 outputValueA;
        uint256 outputValueB;

        (outputValueA, outputValueB, ) = _convert(
            getRealAztecAsset(_token0),
            emptyAsset,
            AztecTypes.AztecAsset({
                id: getNextNonce(),
                erc20Address: address(0),
                assetType: AztecTypes.AztecAssetType.VIRTUAL
            }),
            getRealAztecAsset(_token1),
            _deposit,
            data
        );
        //vm.stopPrank();
        (, , uint256 amount0, uint256 amount1, , , , , ) = syncBridge.getDeposit(1);

        (uint256 redeem0, uint256 redeem1) = _redeem(outputValueA, getNextNonce() - 1, _token0, _token1);

        {
            (uint160 originalPrice, , , , , , ) = IUniswapV3Pool(pool).slot0();

            //sqrt(10^b-a * token0Price) * 2**96
            originalPrice = originalPrice / (2**48); //sqrt(10^b-a * token0Price) * 2**48
            originalPrice = originalPrice**2; //10^b-a * token0Price * 2**96

            //convert amount0 to usdt value / qty
            //sum converted amount with amount1 usdt qty
            uint256 total1ValueBefore = amount1 + ((amount0 * originalPrice) / 2**96);
            //convert redeem0 to usdt value qty
            //sum converted redeemed amount with redeem1 usdt qty
            uint256 total1ValueAfter = redeem1 + ((redeem0 * originalPrice) / 2**96);
            //convert amount1 to eth equivalent qty / value
            //sum converted amount1 eth value with amount0 eth value for total eth value
            uint256 total0ValueBefore = amount0 + ((amount1 * (2**96)) / originalPrice);
            //convert redeem1 to equivalent eth value
            //sum converted redeem1 equivalent eth value with redeem0 eth value for total eth value
            uint256 total0ValueAfter = redeem0 + ((redeem1 * (2**96)) / originalPrice);
            assertTrue(
                (total0ValueBefore * 95) / 100 <= total0ValueAfter ||
                    (total1ValueBefore * 95) / 100 <= total1ValueAfter,
                "Equivalent values in either token did not match upon redemption"
            );
        }
    }

    function _redeem(
        uint256 _inputValue,
        uint256 _nonce,
        address _token0,
        address _token1
    ) internal returns (uint256, uint256) {
        AztecTypes.AztecAsset memory outputAssetA = getRealAztecAsset(_token0);

        AztecTypes.AztecAsset memory outputAssetB = getRealAztecAsset(_token1);
        (uint256 outputValueA, uint256 outputValueB, ) = _convert(
            AztecTypes.AztecAsset({id: _nonce, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL}),
            emptyAsset,
            outputAssetA,
            outputAssetB,
            _inputValue,
            0
        );
        //vm.stopPrank();
        ///sort in terms of token0 or token1
        return (
            outputAssetA.erc20Address < outputAssetB.erc20Address
                ? (outputValueA, outputValueB)
                : (outputValueB, outputValueA)
        );
    }

    function _limitsOfPoolSwap(address _pool, address _token) internal returns (uint256, uint256) {
        //there are max liquidity constraints per pool, therefore it makes sense to define custom limits
        //on a per pool basis rather than a per token basis alone.
        //USDT WETH 500
        if (_pool == 0x11b815efB8f581194ae79006d24E0d814B7697F6) {
            if (_token == USDT) return (1000000000000, 1000000000000000000);
            else if (_token == WETH) return (16990826690438413, 50000000 * (10**18));
        }
        //WETH USDC 3000
        else if (_pool == 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8) {
            if (_token == WETH) return (16990826690438413, 218809284046322613163859525526366);
            else if (_token == USDC) return (1000000000000, 681295379303178355619856090732);
        }
        //USDT WBTC 3000
        else if (_pool == 0x9Db9e0e53058C89e5B94e29621a205198648425B) {
            if (_token == USDT) return (10000000, 26567527292104433082061);
            else if (_token == WBTC) return (10000, 292678394196);
        }
        //WETH WBTC 3000
        else if (_pool == 0xCBCdF9626bC03E24f779434178A73a0B4bad62eD) {
            if (_token == WETH) return (1699082669043840, 2188092840463226131638595111);
            else if (_token == WBTC) return (100000, 7000 * (10**8));
        }
        //USDC WBTC 3000
        else if (_pool == 0x99ac8cA7087fA4A2A1FB6357269965A2014ABc35) {
            if (_token == USDC) return (1000000, 10659313385221300);
            else if (_token == WBTC) return (100000, 4228925722264);
        }
    }

    function _convert(
        AztecTypes.AztecAsset memory _inputAssetA,
        AztecTypes.AztecAsset memory _inputAssetB,
        AztecTypes.AztecAsset memory _outputAssetA,
        AztecTypes.AztecAsset memory _outputAssetB,
        uint256 _inputValue,
        uint64 _auxData
    )
        internal
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        )
    {
        uint256 bId = ROLLUP_PROCESSOR.getSupportedBridgesLength();
        uint256 bridgeCallData = encodeBridgeCallData(
            bId,
            _inputAssetA,
            _inputAssetB,
            _outputAssetA,
            _outputAssetB,
            _auxData
        );
        (outputValueA, outputValueB, ) = sendDefiRollup(bridgeCallData, _inputValue);
    }

    function _limitsOfPool(address _pool)
        internal
        returns (
            uint256,
            uint256,
            uint256,
            uint256
        )
    {
        //there are max liquidity constraints per pool, therefore it makes sense to define custom limits
        //on a per pool basis rather than a per token basis alone.
        //USDT WETH 500
        if (_pool == 0x11b815efB8f581194ae79006d24E0d814B7697F6) {
            //WETH first, USDT second
            return (16990826690438413, 1227845160188079285473, 1000000000000, 1000000000000000000);
        }
        //WETH USDC 3000
        else if (_pool == 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8) {
            return (10000000, (10**(18)), 16990826690438413, 10**(30));
        }
        //USDT WBTC 3000
        else if (_pool == 0x9Db9e0e53058C89e5B94e29621a205198648425B) {
            return (10000, 40 * (10**14), 10000000, 10**18);
        }
        //WETH WBTC 3000
        else if (_pool == 0xCBCdF9626bC03E24f779434178A73a0B4bad62eD) {
            return (100000, 2790826690438412, 1699082669043840, 1188092840463226131638595111);
        }
        //USDC WBTC 3000
        else if (_pool == 0x99ac8cA7087fA4A2A1FB6357269965A2014ABc35) {
            return (100000, 16990826690438413, 1000000, 10659313385221300);
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
}
