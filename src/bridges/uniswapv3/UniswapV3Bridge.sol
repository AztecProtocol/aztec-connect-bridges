pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import {SafeMath} from "../../../node_modules/@openzeppelin/contracts/utils/math/SafeMath.sol";
import {INonfungiblePositionManager} from './interfaces/INonfungiblePositionManager.sol';
import {TransferHelper} from './libraries/TransferHelper.sol';
import {ISwapRouter} from './interfaces/ISwapRouter.sol';
import {IERC20} from './interfaces/IERC20.sol';
import {IERC721Receiver} from '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import {console} from "../../test/console.sol";
import '../../interfaces/IRollupProcessor.sol';
import './interfaces/IUniswapV3Factory.sol';
import './base/LiquidityManagement.sol';
import './interfaces/IWETH9.sol';

interface ICallback{
function MockCallback(address _token0, address _token1, uint24 fee, int24 tickSpacing, uint128 maxLiquidityPerTick) external;
function restoreOriginalCodeCallback(bytes calldata originalCode) external;
}


contract UniswapV3Bridge is LiquidityManagement, IERC721Receiver {

    using SafeMath for uint256;
    

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

    mapping(uint256 => Deposit) public deposits; //interaction nonce -> deposit struct
    
    /* 
        IMMUTABLE VARIABLES
    */

    address public immutable owner;
    IRollupProcessor public immutable rollupProcessor;
    ISwapRouter public immutable swapRouter;
    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    IUniswapV3Factory public immutable uniswapFactory; 
    IWETH9 public immutable WETH;

    /* 
        NOT USED IN PRODUCTION, FOR TESTING PURPOSES ONLY
    */
    
    bytes public originalCode;
    
    constructor(address _rollupProcessor, address _router, address _nonfungiblePositionManager, address _factory, address _WETH ) 
    PeripheryImmutableState(_factory, _WETH) public {

        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        rollupProcessor = IRollupProcessor(_rollupProcessor);
        swapRouter = ISwapRouter(_router);
        WETH = IWETH9(_WETH);
        uniswapFactory = IUniswapV3Factory(_factory);
        owner = msg.sender;
    }
    
    function onERC721Received(
        address operator,
        address,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function getPresentValue(uint256 interactionNonce) external view returns (uint128 tokensOwed0, uint128 tokensOwed1){
        
        uint256 tokenId = deposits[interactionNonce].tokenId;
        
            (   ,
            ,
            ,
            ,
            ,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,
            
        ) =
            nonfungiblePositionManager.positions(tokenId);
        //calculate using LIquidityAmounts.sol library 
    }
    
    function getMarketSize(address tokenA, address tokenB, uint24 fee) external view returns (uint256 balanceA, uint256 balanceB){
        address pool = uniswapFactory.getPool(tokenA, tokenB, fee);
        balanceA = IERC20(tokenA).balanceOf(pool);
        balanceB = IERC20(tokenB).balanceOf(pool);
    }

    function getDeposit(uint256 interactionNonce) external view returns (
        uint256 ,
        uint128 , 
        uint256 ,
        uint256 ,
        int24 ,
        int24 ,
        uint24 ,
        address , 
        address )
    {
        Deposit memory deposit = deposits[interactionNonce];
        
        return (
        deposit.tokenId,deposit.liquidity,deposit.amount0,
        deposit.amount1,deposit.tickLower,deposit.tickUpper,
        deposit.fee,deposit.token0,deposit.token1
        );
    }

    function _withdraw(
        uint256 interactionNonce,
        uint128 liquidity
        ) 
        internal returns ( uint256,  uint256) {

        // get liquidity data for tokenId
        // amount0Min and amount1Min are price slippage checks
        // if the amount received after burning is not greater than these minimums, transaction will fail
        console.log(liquidity, "input liq");
        {
             (
           ,
            ,
            ,
           ,
            ,
            ,
            ,
            uint128 liq ,
           ,
            ,
            ,
            
        ) = nonfungiblePositionManager.positions((deposits[interactionNonce].tokenId) );
            console.log(liq, "pos liq");
        }
        
        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: deposits[interactionNonce].tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });


        (uint256 amount0Out, uint256 amount1Out) = nonfungiblePositionManager.decreaseLiquidity(params);

        console.log(amount0Out, amount1Out, "decrease");

        {
            (uint256 redeemed0, uint256 redeemed1) = _collect(deposits[interactionNonce].tokenId);
            
            //take care of dust
            //_sweepDust(interactionNonce, amount0Out, amount1Out, redeemed0, redeemed1);
        }

        //send liquidity back to owner
        //_approveTo(interactionNonce, amount0, amount1, address(rollupProcessor) );
        //bridge accounting

        require(deposits[interactionNonce].liquidity >= liquidity, "!GTE");
        deposits[interactionNonce].liquidity = deposits[interactionNonce].liquidity-liquidity;
        
        //decided this is irrelevant, as it triggers arithmetic overflow often, because in certain scenarios, amount0 is less
        //than amount0Out. for example if ETH price went up in DAI alot, then it could trigger the error.further more, 
        //the bridges does not use amount0 or amount1 in deposits mapping for much.
        //deposits[interactionNonce].amount0 =  deposits[interactionNonce].amount0 > amount0Out ? deposits[interactionNonce].amount0- ;
        //deposits[interactionNonce].amount1 = deposits[interactionNonce].amount1.sub(amount1Out);   
        //we use the following instead, which is used by asyncbridge as a record of how much output the position received
        //after withdrawal. 

        deposits[interactionNonce].amount0 = amount0Out;
        deposits[interactionNonce].amount1 = amount1Out;

        return (amount0Out, amount1Out);
    }
    function _sweepDust(uint256 interactionNonce, uint256 amount0, uint256 amount1, uint256 collect0, uint256 collect1) internal
    returns (
        uint256 ,
        uint256 
    ) {
            require(amount0 >= collect0 && amount1 >= collect1, ">=");
            if(amount0-collect0 > 0 || amount1-collect1 > 0 )
            {
            
                IUniswapV3Pool pool = IUniswapV3Pool(uniswapFactory.getPool(deposits[interactionNonce].token0,deposits[interactionNonce].token1, deposits[interactionNonce].fee)
                );    
                console.log("2nd");

                (uint256 out0 , uint256 out1) =     
                    pool.collect(
                    address(this),
                    deposits[interactionNonce].tickLower,
                    deposits[interactionNonce].tickUpper,
                    uint128(amount0-collect0),
                    uint128(amount1-collect1)
                );
                amount0 += out0;
                amount1 += out1;
            }
        
        return (amount0, amount1);
    }

    function _collect(uint256 tokenId) internal returns (uint256 amount0, uint256 amount1) {        
        // Caller must own the ERC721 position        
        // set amount0Max and amount1Max to uint256.max to collect all fees        
        // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({ 
        tokenId: tokenId, recipient: address(this), amount0Max: type(uint128).max, amount1Max: type(uint128).max
        });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);
        console.log(amount0, amount1, "collect");

    }

    function _sendTo(
        uint256 interactionNonce,
        uint256 amount0,
        uint256 amount1, address _to
    ) internal {
        address token0 = deposits[interactionNonce].token0;
        address token1 = deposits[interactionNonce].token1;
        TransferHelper.safeTransfer(token0, _to, amount0);
        TransferHelper.safeTransfer(token1, _to, amount1);
    }

    function _approveTo(
        uint256 interactionNonce,
        uint256 amount0,
        uint256 amount1, address _to
    ) internal {
        address token0 = deposits[interactionNonce].token0;
        address token1 = deposits[interactionNonce].token1;
        TransferHelper.safeApprove(token0, _to, amount0);
        TransferHelper.safeApprove(token1, _to, amount1);
    }

    function _createDeposit( uint256 tokenId, uint256 interactionNonce, uint256 amount0, uint256 amount1, uint24 fee) internal {
        
        (   ,
            ,
            address token0,
            address token1,
            ,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,
            
        ) =
            nonfungiblePositionManager.positions(tokenId);

        // set data for position
        deposits[interactionNonce] = Deposit({
                        tokenId: tokenId,
                        liquidity: liquidity, 
                        amount0: amount0, 
                        amount1: amount1,
                        tickLower: tickLower, 
                        tickUpper: tickUpper, 
                        fee: fee, 
                        token0: token0, 
                        token1: token1
                        });

    }
     function _mintNewPosition( address token0, address token1, uint256 amount0ToMint, uint256 amount1ToMint,
        int24 tickLower, int24 tickUpper, uint24 fee, uint256 interactionNonce)
        internal returns (uint128 liquidity, uint256 refund0, uint256 refund1)
    {
       
        TransferHelper.safeApprove(token0, address(nonfungiblePositionManager), amount0ToMint);
        TransferHelper.safeApprove(token1, address(nonfungiblePositionManager), amount1ToMint);
        INonfungiblePositionManager.MintParams memory params =
            INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: fee,
                tickLower: tickLower, 
                tickUpper: tickUpper, 
                amount0Desired: amount0ToMint,
                amount1Desired: amount1ToMint,
                amount0Min: 0,
                amount1Min: 0, 
                recipient: address(this),
                deadline: block.timestamp
            });
        
        
        uint256 amount0; 
        uint256 amount1;
        
        console.log("reached minting");
        
        {
            uint256 tokenId;
            (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);
            console.log(amount0, amount1, "mint");
            console.log("passed minting");
            _createDeposit(tokenId, interactionNonce, amount0, amount1, fee);
            console.log("passed deposit creation");
        }
        
        console.log("reached refunding");
        // Remove allowance and refund in both assets.
        if (amount0 < amount0ToMint) {
            TransferHelper.safeApprove(token0, address(nonfungiblePositionManager), 0);
            refund0 = amount0ToMint - amount0;
            //TransferHelper.safeTransfer(token0, rollupProcessor, refund0);
        }

        if (amount1 < amount1ToMint) {
            TransferHelper.safeApprove(token1, address(nonfungiblePositionManager), 0);
            refund1 = amount1ToMint - amount1;
            //TransferHelper.safeTransfer(token1, rollupProcessor, refund1);
        }
    }
    function _refundConversion(uint256 refund0, uint256 refund1, address refund_address, address token0, address token1, uint24 fee) internal
    returns (uint256 refundedAmount) {
                
        
                //we have refunds in token1, convert to token0 to match outputAssetB
                //or we have refunds in token0, convert to token1 to match outputAssetB
                // The call to `exactInputSingle` executes the swap.
                uint256 amountIn = refund_address == token0 ? refund1 : refund0;
                address tokenIn = refund_address == token0 ? token1 : token0;
                require(IERC20(tokenIn).approve(address(swapRouter), amountIn), "UniswapV3Bridge: APPROVE_FAILED" );
                ISwapRouter.ExactInputSingleParams memory swap_params =
                ISwapRouter.ExactInputSingleParams({
                    tokenIn:  tokenIn,
                    tokenOut: refund_address == token0 ? token0 : token1,
                    fee: fee,
                    recipient: address(this), 
                    deadline: block.timestamp,
                    amountIn: amountIn,
                    amountOutMinimum:  0,
                    sqrtPriceLimitX96: 0
                });

                refundedAmount = swapRouter.exactInputSingle(swap_params);
                console.log(refundedAmount, "refund");
        
    }

}
