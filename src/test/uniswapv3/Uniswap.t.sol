
// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;
pragma experimental ABIEncoderV2;
import "../../../lib/ds-test/src/test.sol";
import {Vm} from "../Vm.sol";
import {console} from "../console.sol";
import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {INonfungiblePositionManager} from '../../bridges/uniswapv3/interfaces/INonfungiblePositionManager.sol';
import {IUniswapV3Factory} from '../../bridges/uniswapv3/interfaces/IUniswapV3Factory.sol';
import {IUniswapV3Pool} from '../../bridges/uniswapv3/interfaces/IUniswapV3Pool.sol';
import {TickMath} from '../../bridges/uniswapv3/libraries/TickMath.sol';
import {SyncUniswapV3Bridge, TransferHelper, ISwapRouter, IQuoter } from "./../../bridges/uniswapv3/SyncUniswapV3Bridge.sol";
import {AsyncUniswapV3Bridge} from "./../../bridges/uniswapv3/AsyncUniswapV3Bridge.sol";
import {AztecTypes} from "./../../aztec/AztecTypes.sol";
import {LiquidityAmounts} from '../../bridges/uniswapv3/libraries/LiquidityAmounts.sol';
import {AztecKeeper} from "./../../bridges/uniswapv3/AztecKeeper.sol";

contract UniswapTest is DSTest {


    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    DefiBridgeProxy defiBridgeProxy;
    RollupProcessor rollupProcessor;

    SyncUniswapV3Bridge syncBridge;
    AsyncUniswapV3Bridge asyncBridge;

    IERC20 constant dai = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant nonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant quoter = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address constant pool = 0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36;

    INonfungiblePositionManager public immutable manager = INonfungiblePositionManager(nonfungiblePositionManager);

        struct Deposit 
    {
        uint256 tokenId;
        uint128 liquidity; 
        uint256 amount0;
        uint256 amount1;
        int24 tickLower;
        int24 tickUpper;
        uint24 fee;  
        address token0; 
        address token1;
    }
    
    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    function setUp() public {
        _aztecPreSetup();

        syncBridge = new SyncUniswapV3Bridge(
            address(rollupProcessor), router, nonfungiblePositionManager, factory, address(WETH), quoter
        );

        asyncBridge = new AsyncUniswapV3Bridge(
            address(rollupProcessor), router, nonfungiblePositionManager, factory, address(WETH), quoter
        );


        vm.deal(address(asyncBridge), uint256(10000) );
        vm.deal(address(syncBridge), uint256(10000) );
        vm.deal(address(this), uint256(10000));



    }
    


    function adjustTickParams(int24 tickLower, int24 tickUpper, address _pool) internal returns ( int24 newTickLower, int24 newTickUpper) {
        //adjust the params s.t. they conform to tick spacing and do not fail the tick % tickSpacing == 0 check
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        newTickLower = tickLower % pool.tickSpacing() == 0 ? tickLower : tickLower - (tickLower % pool.tickSpacing() );
        newTickUpper = tickUpper % pool.tickSpacing() == 0 ? tickUpper : tickUpper - (tickUpper % pool.tickSpacing() );
    
    }


    function assumptions(uint256 deposit) internal {
        if(address(dai) == 0xdAC17F958D2ee523a2206206994597C13D831ec7){
            vm.assume(deposit <= 3769678424353192924097187526);
        }
    }
    
    function testAsyncLimitOrderKeeper(uint256 _deposit) public {

        vm.assume(_deposit >= 1000000000000000);
        vm.assume(_deposit <= 60048070258392067512707354988);
        uint256 depositAmount = _deposit;
        _setTokenBalance(address(dai), address(rollupProcessor), depositAmount, 2);
        
        uint64 data;

        
        
                
        {   
            (uint160 price, int24 currentTick, , , , , ) = IUniswapV3Pool(pool).slot0();
            price = (price * 80)/100; //increase price by 1%
            currentTick = TickMath.getTickAtSqrtRatio(price); //get new current tick
            //buy limit
            (int24 _a, int24 _b ) = adjustTickParams( currentTick - (20*IUniswapV3Pool(pool).tickSpacing()),currentTick + (20*IUniswapV3Pool(pool).tickSpacing()), pool );
            uint24 a = uint24(_a);
            uint24 b = uint24(_b);
            uint48 ticks = (uint48(a) << 24) | uint48(b);
            uint8 fee =  uint8(30);
            uint8 days_to_cancel = 0;
            uint16 last16 = (uint16(fee) << 8 | uint16(days_to_cancel) );
            data = (uint64(ticks) << 16) | uint64(last16);

        }


        
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(dai),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory inputAssetB = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.NOT_USED
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(WETH),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetB = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(dai),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        

        {

            rollupProcessor.convert(
                    address(asyncBridge),
                    inputAssetA,
                    inputAssetB,
                    outputAssetA,
                    outputAssetB,
                    depositAmount,
                    1,
                    data
                );

        }
        
        if(true)
        {
            

            //_replaceWithMock(IUniswapV3Pool(pool).token0(), IUniswapV3Pool(pool).token1(),  IUniswapV3Pool(pool).fee(), IUniswapV3Pool(pool).tickSpacing(), IUniswapV3Pool(pool).maxLiquidityPerTick() );

            (         
            ,
            , 
            ,
            ,
            int24 tickLower ,
            int24 tickUpper,
            ,
            , 
            ) = asyncBridge.getDeposit(1);

            
            _setTokenBalance(address(WETH), address(this), WETH.totalSupply(), 3);


            TransferHelper.safeApprove(address(WETH), router, WETH.totalSupply());
            {
                ISwapRouter.ExactInputSingleParams memory swap_params =
                ISwapRouter.ExactInputSingleParams({
                tokenIn:  address(WETH),
                tokenOut: address(dai),
                fee: 3000,
                recipient: address(this), 
                deadline: block.timestamp,
                amountIn: 100 * 10**18, //sell 100 eth at a time until price is lower
                amountOutMinimum: 0, //flashbots
                sqrtPriceLimitX96: 0
            });

           (uint160 new_price, , , , , , ) = IUniswapV3Pool(pool).slot0();

                while( !(tickLower <= TickMath.getTickAtSqrtRatio(new_price) && TickMath.getTickAtSqrtRatio(new_price) <=  tickUpper ) ){
                    uint256 amountOut = ISwapRouter(router).exactInputSingle(swap_params);
                    (new_price, , , , , , ) = IUniswapV3Pool(pool).slot0();
                    console.log(new_price, "prices");
                }
            
            }


        }
        
        
        ( ,
         , 
        uint256 amount0,
        uint256 amount1,
         ,
         ,
         ,
         , 
        ) = asyncBridge.getDeposit(1);

        console.log("trigger");
        AztecKeeper keeper = new AztecKeeper(1, factory, address(rollupProcessor), address(asyncBridge) );

        {
            uint256[] memory interactions = new uint256[](1);
            interactions[0] = 1;
            (bool upkeep, bytes memory performData) = keeper.checkUpkeep(abi.encode(interactions));
            keeper.performUpkeep(performData);
        }

        //(uint256 out0, uint256 out1) = asyncBridge.trigger(1);
        //rollupProcessor.processAsyncDeFiInteraction(1);

        //we use require isntead of assertEq because the price manipulation we use in this always results in more output than input
        //so they never are equal
        //_marginOfError(amount0, out0, amount1, out1, 100000);
        //assertTrue((out0 + out1) >= (amount0+amount1)*99999/100000, "> .000001 diff");
        
    }

    function testAsyncLimitOrder(uint256 _deposit) public {

        vm.assume(_deposit >= 1000000000000000);
        vm.assume(_deposit <= 60048070258392067512707354988);
        uint256 depositAmount = _deposit;
        _setTokenBalance(address(dai), address(rollupProcessor), depositAmount, 2);
        
        uint64 data;

        
        
                
        {   
            (uint160 price, int24 currentTick, , , , , ) = IUniswapV3Pool(pool).slot0();
            price = (price * 80)/100; //increase price by 1%
            currentTick = TickMath.getTickAtSqrtRatio(price); //get new current tick
            //buy limit
            (int24 _a, int24 _b ) = adjustTickParams( currentTick - (20*IUniswapV3Pool(pool).tickSpacing()),currentTick + (20*IUniswapV3Pool(pool).tickSpacing()), pool );
            uint24 a = uint24(_a);
            uint24 b = uint24(_b);
            uint48 ticks = (uint48(a) << 24) | uint48(b);
            uint8 fee =  uint8(30);
            uint8 days_to_cancel = 0;
            uint16 last16 = (uint16(fee) << 8 | uint16(days_to_cancel) );
            data = (uint64(ticks) << 16) | uint64(last16);

        }


        
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(dai),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory inputAssetB = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.NOT_USED
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(WETH),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetB = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(dai),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        

        {

            rollupProcessor.convert(
                    address(asyncBridge),
                    inputAssetA,
                    inputAssetB,
                    outputAssetA,
                    outputAssetB,
                    depositAmount,
                    1,
                    data
                );

        }
        
        if(true)
        {
            

            //_replaceWithMock(IUniswapV3Pool(pool).token0(), IUniswapV3Pool(pool).token1(),  IUniswapV3Pool(pool).fee(), IUniswapV3Pool(pool).tickSpacing(), IUniswapV3Pool(pool).maxLiquidityPerTick() );

            (         
            ,
            , 
            ,
            ,
            int24 tickLower ,
            int24 tickUpper,
            ,
            , 
            ) = asyncBridge.getDeposit(1);

            
            _setTokenBalance(address(WETH), address(this), WETH.totalSupply(), 3);


            TransferHelper.safeApprove(address(WETH), router, WETH.totalSupply());
            {
                ISwapRouter.ExactInputSingleParams memory swap_params =
                ISwapRouter.ExactInputSingleParams({
                tokenIn:  address(WETH),
                tokenOut: address(dai),
                fee: 3000,
                recipient: address(this), 
                deadline: block.timestamp,
                amountIn: 100 * 10**18, //sell 100 eth at a time until price is lower
                amountOutMinimum: 0, //flashbots
                sqrtPriceLimitX96: 0
            });

           (uint160 new_price, , , , , , ) = IUniswapV3Pool(pool).slot0();

                while( !(tickLower <= TickMath.getTickAtSqrtRatio(new_price) && TickMath.getTickAtSqrtRatio(new_price) <=  tickUpper ) ){
                    uint256 amountOut = ISwapRouter(router).exactInputSingle(swap_params);
                    (new_price, , , , , , ) = IUniswapV3Pool(pool).slot0();
                    console.log(new_price, "prices");
                }
            
            }


        }
        
        
        ( ,
         , 
        uint256 amount0,
        uint256 amount1,
         ,
         ,
         ,
         , 
        ) = asyncBridge.getDeposit(1);

        console.log("trigger");
        (uint256 out0, uint256 out1) = asyncBridge.trigger(1);
        rollupProcessor.processAsyncDeFiInteraction(1);

        //we use require isntead of assertEq because the price manipulation we use in this always results in more output than input
        //so they never are equal
        //_marginOfError(amount0, out0, amount1, out1, 100000);
        assertTrue((out0 + out1) >= (amount0+amount1)*99999/100000, "> .000001 diff");
        
    }


    

    function testAsyncLimitOrderThenCancel(uint256 _deposit) public {

        vm.assume(_deposit >= 1000000000000);
        assumptions(_deposit);

        vm.assume(_deposit <= 4844169603388782940195207690438998); //maxLiquidity is reached here, causing LO error code. 
        //this is a logical upper boundary

        uint256 depositAmount = _deposit;
        
        _setTokenBalance(address(dai), address(rollupProcessor), depositAmount, 2);
        
        uint64 data;

        
        
                
        {   
            (uint160 price, int24 currentTick, , , , , ) = IUniswapV3Pool(pool).slot0();
            price = (price * 50)/100; //decrease price by 50%
            currentTick = TickMath.getTickAtSqrtRatio(price); //get new current tick
            //buy limit
            (int24 _a, int24 _b ) = adjustTickParams( currentTick - (2*IUniswapV3Pool(pool).tickSpacing()),currentTick + (2*IUniswapV3Pool(pool).tickSpacing()) , pool );
            uint24 a = uint24(_a);
            uint24 b = uint24(_b);
            uint48 ticks = (uint48(a) << 24) | uint48(b);
            uint8 fee =  uint8(30);
            uint8 days_to_cancel = 0;
            uint16 last16 = (uint16(fee) << 8 | uint16(days_to_cancel) );
            data = (uint64(ticks) << 16) | uint64(last16);
        }


        
        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(dai),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory inputAssetB = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.NOT_USED
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(WETH),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetB = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(dai),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        

        {

            rollupProcessor.convert(
                    address(asyncBridge),
                    inputAssetA,
                    inputAssetB,
                    outputAssetA,
                    outputAssetB,
                    depositAmount,
                    1,
                    data
                );

        }
        
        ( ,
         , 
        uint256 amount0,
        uint256 amount1,
         ,
         ,
         ,
         , 
        ) = asyncBridge.getDeposit(1);

        console.log("cancel");
        (uint256 out0, uint256 out1) = asyncBridge.cancel(1);
        rollupProcessor.processAsyncDeFiInteraction(1);

        
        //one of the outputs will always be 0, we will onyl need to test the non zero one

        assertTrue(
            (out0 == 0 ? out1 : out0) >= (amount0 == 0 ? amount1 : amount0 )*99999/100000 , 
            "failed .000001 margin"
        );

    }

    function testTwoPartMint(uint256 _deposit, uint256 _ethDeposit) public {
        //revert();


        vm.assume(_deposit >= 1000000000000 && _ethDeposit >= 100000000000000);

        //this is the point at which maxLiquidityPerTick is triggered. fair to say at this point the test is passing and this is
        //the logical upper boundary for the test range, as these numbers are something like 218 trillion eth and
        //several hundred trillion dai, or something else ridiculous
        vm.assume(_deposit <= 18543829948235660536859190385180672 && _ethDeposit <= 218809284046322613163859525526366);

        uint256 depositAmount = _deposit;
        _setTokenBalance(address(dai), address(rollupProcessor), depositAmount, 2);
        uint256 wethDeposit = _ethDeposit;
        _setTokenBalance(address(WETH), address(rollupProcessor), wethDeposit, 3);

        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(dai),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory inputAssetB = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.NOT_USED
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.VIRTUAL
        });

        AztecTypes.AztecAsset memory outputAssetB = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.NOT_USED
        });
        
        uint256 virtualNoteAmount; 

        {

            (
                uint256 outputValueA,
                uint256 outputValueB,

            ) = rollupProcessor.convert(
                    address(syncBridge),
                    inputAssetA,
                    inputAssetB,
                    outputAssetA,
                    outputAssetB,
                    depositAmount,
                    1,
                    0
                );

            uint256 bridgeDai = dai.balanceOf(address(syncBridge));
            virtualNoteAmount = outputValueA;

            assertEq(
                depositAmount,
                bridgeDai,
                "Balances must match"
            );
        
        }

        inputAssetA = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(WETH),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        inputAssetB = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.VIRTUAL
        });

        outputAssetA = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.VIRTUAL
        });

        outputAssetB = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(dai),
            assetType: AztecTypes.AztecAssetType.ERC20
        });


        {
            uint64 data;
        
            {   (int24 _a, int24 _b ) = adjustTickParams( TickMath.MIN_TICK, TickMath.MAX_TICK, pool );
                uint24 a = uint24(_a);
                uint24 b = uint24(_b);
                uint48 ticks = (uint48(a) << 24) | uint48(b);
                uint16 fee =  3000;
                data = (uint64(ticks) << 16) | uint64(fee);
            }
            
            (
                uint256 callTwoOutputValueA, , 
    
            ) = rollupProcessor.convert(
                    address(syncBridge),
                    inputAssetA,
                    inputAssetB,
                    outputAssetA,
                    outputAssetB,
                    wethDeposit,
                    2,
                    data
                );

            uint256 callTwoVirtualNoteAmount = callTwoOutputValueA;

            ( ,
              , 
            uint256 amount0,
            uint256 amount1,
            ,
            ,
            ,
            , 
            ) = syncBridge.getDeposit(2);

            (uint256 redeem0, uint256 redeem1) = _redeem(callTwoVirtualNoteAmount, 3);
            
            {
                //we set the margin of error to be 1/100,000 of the total initial size or .001%
                _marginOfError(amount0, redeem0, amount1, redeem1, 100000);
            
            }
           
        }

    }

    function testMintBySwap(uint256 _depositAmount) public {
       // revert();
        vm.assume(_depositAmount != 0);
        vm.assume(_depositAmount != 1); //this is necessary on top of the standard 0 boundary case because half of the depositAmount is 
        //swapped , and the calculation of depositAmount/2 as the amountIn results in 0  when depositAmount is 1.
        vm.assume(_depositAmount >= 1000000000000);
        //this is the point at which when the nonfungiblePositionManager's call to slot0() fails and the txn is reverted, presumably
        //because there is some sort of error in sqrtPriceX96 after the massive swap ? regardless this number is greater than several quadrillion dai, 
        //so i feel this is a logical upper boundary
        vm.assume(_depositAmount <= 506840802329476492815900036);
        uint256 depositAmount = _depositAmount;
        console.log("setting dai balance");
        _setTokenBalance(address(dai), address(rollupProcessor), depositAmount, 2);


        AztecTypes.AztecAsset memory inputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(dai),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory inputAssetB = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.NOT_USED
        });

        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.VIRTUAL
        });
        AztecTypes.AztecAsset memory outputAssetB = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: address(WETH),
            assetType: AztecTypes.AztecAssetType.ERC20
        });
        
        uint64 data;
        //pack params into data

        {
            /*
            IUniswapV3Pool pool = IUniswapV3Pool(IUniswapV3Factory(factory).getPool(address(dai), address(WETH), 3000 ) );
            (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
            int24 currentTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
            */
            address pool = IUniswapV3Factory(factory).getPool(address(dai), address(WETH), 3000);
            (int24 _a, int24 _b ) = adjustTickParams( TickMath.MIN_TICK, TickMath.MAX_TICK, pool );
            uint24 a = uint24(_a);
            uint24 b = uint24(_b);
            uint48 ticks = (uint48(a) << 24) | uint48(b);
            uint16 fee =  3000;
            data = (uint64(ticks) << 16) | uint64(fee);
        }
        


        
        (
            uint256 outputValueA,
            uint256 outputValueB,

        ) = rollupProcessor.convert(
                address(syncBridge),
                inputAssetA,
                inputAssetB,
                outputAssetA,
                outputAssetB,
                depositAmount,
                1,
                data
            );
        
         (
         ,
         , 
        uint256 amount0,
        uint256 amount1,
         ,
         ,
         ,
         , 
         ) = syncBridge.getDeposit(1);

        (uint256 redeem0, uint256 redeem1) = _redeem(outputValueA, 2);
        
        console.log("after redeem");
        console.log(amount0, redeem0, "token0");
        console.log(amount1, redeem1, "token1");
       

        _marginOfError(amount0, redeem0, amount1, redeem1, 100000/20);

        //Note (s)
        //at 25 million ethereum the .001 margin of error is breached
        //at 126 million eth the .005 MoE is breached
        //at 253 million eth the .01 MoE is breached
        //at 605 million eth the .05 MoE is breached
    }
    

    
    function _marginOfError(uint256 amount0, uint256 redeem0, uint256 amount1, uint256 redeem1, uint256 marginFrac) internal {
        
        //tests for rounding error
        
        //necessary when testing smaller values, which have larger margin % but are smaller in absolute terms
        //e.g. 1000 wei -> 999 wei, which is .1% error, very high


        //we dont care if the amount redeemed is more than the amount minted, only less than

        uint256 SCALE = 1000000;

        //sometimes when 1 output is much less than the input , the other output is much larger than its original input
        //e.g. token0 input of 100, output of 99, but token1 input of 100 and output of 101
        console.log(redeem0*SCALE / amount0, redeem1 *SCALE / amount1, "percents");
        
        uint256 sum = (redeem0*SCALE /amount0) + (redeem1 * SCALE / amount1);
        
        assertTrue( sum >= (2 *SCALE) - SCALE/marginFrac, "not within %margin");
    }

    function _redeem(uint256 inputValue, uint256 nonce) internal returns (uint256, uint256) {




        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: nonce,
            erc20Address: address(WETH),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetB = AztecTypes.AztecAsset({
            id: nonce,
            erc20Address: address(dai),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        (
            uint256 outputValueA,
            uint256 outputValueB,
           
        ) = rollupProcessor.convert(
                address(syncBridge),
                AztecTypes.AztecAsset({
            id: nonce-1,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.VIRTUAL
             }),
                AztecTypes.AztecAsset({
            id: nonce,
            erc20Address: address(0),
            assetType: AztecTypes.AztecAssetType.NOT_USED
            }),
                outputAssetA,
                outputAssetB,
                inputValue,
                nonce,
                0
            );
        ///sort in terms of token0 or token1
        return ( outputAssetA.erc20Address < outputAssetB.erc20Address ? (outputValueA, outputValueB) :  (outputValueB, outputValueA) );
    }



    function assertNotEq(address a, address b) internal {
        if (a == b) {
            emit log("Error: a != b not satisfied [address]");
            emit log_named_address("  Expected", b);
            emit log_named_address("    Actual", a);
            fail();
        }
    }


    function _setTokenBalance(
        address token,
        address user,
        uint256 balance,
        uint256 slot
    ) internal {
        // May vary depending on token

        vm.store(
            token,
            keccak256(abi.encode(user, slot)),
            bytes32(uint256(balance))
        );

        assertEq(IERC20(token).balanceOf(user), balance, "wrong balance");
    }



}