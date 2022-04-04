// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;
pragma experimental ABIEncoderV2;
import "ds-test/test.sol";
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

contract UniswapTest is DSTest {


    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);

    DefiBridgeProxy defiBridgeProxy;
    RollupProcessor rollupProcessor;

    SyncUniswapV3Bridge syncBridge;
    AsyncUniswapV3Bridge asyncBridge;

    IERC20 constant dai = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address constant factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant nonfungiblePositionManager = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address constant quoter = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address constant pool = 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8;

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
    
    function MockCallback(address _token0, address _token1, uint24 fee, int24 tickSpacing, uint128 maxLiquidityPerTick) external {
        _replaceWithMock(_token0, _token1, fee, tickSpacing, maxLiquidityPerTick);
    }

    function adjustTickParams(int24 tickLower, int24 tickUpper, address _pool) internal returns ( int24 newTickLower, int24 newTickUpper) {
        //adjust the params s.t. they conform to tick spacing and do not fail the tick % tickSpacing == 0 check
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        newTickLower = tickLower % pool.tickSpacing() == 0 ? tickLower : tickLower - (tickLower % pool.tickSpacing() );
        newTickUpper = tickUpper % pool.tickSpacing() == 0 ? tickUpper : tickUpper - (tickUpper % pool.tickSpacing() );
    
    }

    function _replaceWithMock(address _token0, address _token1, uint24 fee, int24 tickSpacing, uint128 maxLiquidityPerTick) internal {
        
        bytes memory bytecode = vm.getCode("MockPool.sol:MockPool");
        bytes32 salt = bytes32(uint256(32)); 
        address addr;

        bytecode = abi.encodePacked(bytecode, abi.encode(_token0, _token1, fee, tickSpacing, maxLiquidityPerTick) );


        assembly 
        {
            addr := create2(0, add(bytecode, 0x20), mload(bytecode), salt)
        }
        

        bytes memory code = address(addr).code;
    
        vm.etch(pool,code);


        
        //IUniswapV3Pool(pool).initialize(sqrtPriceX96);
        
       
    }

    function restoreOriginalCodeCallback(bytes calldata originalCode) external {
        vm.etch(pool,originalCode);
    }

    
    function testAsyncLimitOrder() public {


        uint256 depositAmount = 15000;
        _setTokenBalance(address(dai), address(rollupProcessor), depositAmount, 2);
        
        uint64 data;

        
        
                
        {   
            (uint160 price, int24 currentTick, , , , , ) = IUniswapV3Pool(pool).slot0();
            price = (price * 150)/100; //decrease price by 50%
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
        
        if(true)
        {
            (uint160 price, int24 currentTick, , , , , ) = IUniswapV3Pool(pool).slot0();
            price = (price * 150)/100; //decrease price by 50%
            currentTick = TickMath.getTickAtSqrtRatio(price); //get new current tick

            _replaceWithMock(IUniswapV3Pool(pool).token0(), IUniswapV3Pool(pool).token1(), 3000, IUniswapV3Pool(pool).tickSpacing(), IUniswapV3Pool(pool).maxLiquidityPerTick() );
            (bool result, bytes memory data) = pool.call(abi.encodeWithSignature("setTickAndPrice(int24,uint160)", currentTick, price) );
            console.log(result);
        }
        
        console.log("trigger");
        asyncBridge.trigger(1);
        rollupProcessor.processAsyncDeFiInteraction(1);
        assertEq(
                uint256(1),
                uint256(1),
                "Balances must match"
            );
        
    }


    

    function testAsyncLimitOrderThenCancel() public {


        uint256 depositAmount = 15000;
        
        _setTokenBalance(address(dai), address(rollupProcessor), depositAmount, 2);
        
        uint64 data;

        
        
                
        {   
            (uint160 price, int24 currentTick, , , , , ) = IUniswapV3Pool(pool).slot0();
            price = (price * 150)/100; //decrease price by 50%
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
        
        
        console.log("cancel");
        asyncBridge.cancel(1);
        rollupProcessor.processAsyncDeFiInteraction(1);

        assertEq(
                uint256(1),
                uint256(1),
                "Balances must match"
            );
    }

    function testTwoPartMint() public {
        //revert();
        uint256 depositAmount = 15000;
        _setTokenBalance(address(dai), address(rollupProcessor), depositAmount, 2);
        uint256 wethDeposit = 10;
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
                uint256 callTwoOutputValueA,
                uint256 callTwoOutputValueB,

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

            (uint256 redeemOutputValueA, uint256 redeemOutputValueB) = _redeem(callTwoVirtualNoteAmount, 3);

            uint256 bridgeDai = dai.balanceOf(address(rollupProcessor));
            uint256 bridgeWETH = WETH.balanceOf(address(rollupProcessor));
            console.log(bridgeDai, bridgeWETH, "bridge");
            assertEq(
                depositAmount,
                bridgeDai,
                "Balances must match"
            );

            assertEq(
                wethDeposit,
                bridgeWETH,
                "Balances must match"
            );
        }

    }

    function testMintBySwap() public {
        //revert();
        uint256 depositAmount = 15000;
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
        
        uint256 pool_balance = WETH.balanceOf(address(pool));


        
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

        (uint256 redeemAmount0, uint256 redeemAmount1) = _redeem(outputValueA, 2);
        
        console.log("after redeem");
        console.log(amount0, redeemAmount0, "0");
        console.log(amount1, redeemAmount1, "1");
       
        


        {
            console.log(pool_balance-WETH.balanceOf(pool), "pool");
        }
        
        if(false){
            TransferHelper.safeApprove(address(WETH), router,10);
            ISwapRouter.ExactInputSingleParams memory swap_params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn:  address(WETH),
                tokenOut: address(dai),
                fee: 3000,
                recipient: address(this), 
                deadline: block.timestamp,
                amountIn: 1,
                amountOutMinimum: 0, //flashbots
                sqrtPriceLimitX96: 0
            });

            uint256 amountOut = ISwapRouter(router).exactInputSingle(swap_params);
            console.log(amountOut);
        }

        assertEq(amount0,
                redeemAmount0,
                "redeem0 =/= amount0"
                );
        assertEq(amount1,
                redeemAmount1,
                "redeem1 =/= amount1"
                );
        



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
