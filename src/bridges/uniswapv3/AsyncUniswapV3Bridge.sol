
// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {IRollupProcessor} from '../../interfaces/IRollupProcessor.sol';
import {AztecTypes} from '../../aztec/AztecTypes.sol';
import {console} from "../../test/console.sol";
import {ISwapRouter} from './interfaces/ISwapRouter.sol';
import {INonfungiblePositionManager} from './interfaces/INonfungiblePositionManager.sol';
import {TickMath} from "./libraries/TickMath.sol";
import "./interfaces/IERC20.sol";
import './interfaces/IUniswapV3Factory.sol';
import "./interfaces/IUniswapV3Pool.sol";
import './UniswapV3Bridge.sol';
import '../../interfaces/IDefiBridge.sol';
import "./interfaces/IQuoter.sol";

// import 'hardhat/console.sol';

contract AsyncUniswapV3Bridge is IDefiBridge, UniswapV3Bridge {
    
    using SafeMath for uint256;
    
    /* 
        STRUCTS AND ENUMS
    */
    
    struct AsyncOrder {
        bool finalisable;
        uint256 expiry;
    }

    /* 
        MUTABLE VARIABLES
    */
    
    mapping(uint256 => AsyncOrder) public asyncOrders;
    
    /* 
        IMMUTABLES/CONSTANT
    */
    
    IQuoter public immutable quoter;
    uint256 public constant MAGIC_NUMBER_DAYS = 60 * 60 * 24; //seconds in a day

    constructor(address _rollupProcessor, address _router, address _nonfungiblePositionManager, address _factory, address _WETH, address _quoter ) 
    UniswapV3Bridge(_rollupProcessor, _router, _nonfungiblePositionManager, _factory, _WETH) public {
    
    quoter = IQuoter(_quoter);

        
    }


    modifier onlyRollup {
    require(msg.sender == address(rollupProcessor), "'UniswapV3Bridge: INVALID_CALLER'");
    _;
    }
    
    function trigger(uint256 interactionNonce) external {
        //for keepers / bot operators to trigger limit orders if conditions are met
        
        if( _checkLimitConditions(interactionNonce) ){
            
            (,,,,,,,,,,uint128 tokensOwed0,uint128 tokensOwed1) = nonfungiblePositionManager.positions(deposits[interactionNonce].tokenId);
            asyncOrders[interactionNonce].finalisable = true;
            (uint256 amount0, uint256 amount1) = _withdraw(interactionNonce, deposits[interactionNonce].liquidity);
            console.log(amount0, amount1, "amounts");
            
            //necessary?
            //require(amount0 == 0 || amount1 == 0 , "NOT_RANGE");

            //implement a fee percentage rather than approving whole thing?
            _approveTo(interactionNonce, tokensOwed0, tokensOwed1, msg.sender);
        
        }
    }
    
    function cancel(uint256 interactionNonce) external {
        if(asyncOrders[interactionNonce].expiry >= block.timestamp){
            asyncOrders[interactionNonce].finalisable = true;
            (uint256 amount0, uint256 amount1) = _withdraw(interactionNonce, deposits[interactionNonce].liquidity);
            console.log(amount0, amount1, "amounts");
            //user may now call processAsyncDefiInteraction successfully
        }
    }
    
    function _checkLimitConditions(uint256 interactionNonce) internal view returns (bool) {
        
        Deposit memory deposit = deposits[interactionNonce];
        IUniswapV3Pool pool = IUniswapV3Pool(uniswapFactory.getPool(deposit.token0, deposit.token1, deposit.fee ) );
        (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
        int24 currentTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        return (
                deposits[interactionNonce].tickLower 
                <= currentTick && currentTick <= 
                deposits[interactionNonce].tickUpper
                );
    }


    function _checkForType(AztecTypes.AztecAsset calldata inputAsset) internal returns (address){
        
        if(inputAsset.assetType == AztecTypes.AztecAssetType.ETH){
            WETH.deposit{value: msg.value}();
            return address(WETH);
        }
        else if(inputAsset.assetType == AztecTypes. AztecAssetType.ERC20){
            return inputAsset.erc20Address;
        }
        else{
            revert('UniswapV3Bridge: INVALID_INPUT');
        }
    }

    function convert(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata inputAssetB, 
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata outputAssetB,
        uint256 inputValue,
        uint256 interactionNonce, 
        uint64  auxData
    )
        external
        payable
        override
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        )
    {
        require(msg.sender == address(rollupProcessor), 'UniswapV3Bridge: INVALID_CALLER');
            
            //Uniswap V3 range limit order
            isAsync = true;
            //sanity checks
            require(inputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED, "INCORRECT_INPUTB");
            address input = _checkForType(inputAssetA);
            address output = _checkForType(outputAssetA);
            // for the refund in case of cancellation
            require(input == _checkForType(outputAssetB), "UniswapV3Bridge: INVALID_MATCH");
            
           
            console.log("passed require checks");

            {
            
                //address pool = uniswapFactory.getPool(input_address,output_address,fee);
                //require(pool != address(0), "NONEXISTENT_POOL");
                
            }

            console.log("reached data initalization lines 152 to 155");

            (address token0, address token1) = input < output ? (input, output) : (output, input);
            uint256 amount0 = input == token0 ? inputValue: 0;
            uint256 amount1 = input == token0 ? 0 : inputValue;
            uint256 nonce = interactionNonce; //avoids stack too deep error
            
            /* 
                to fit all data into 64 bits, we constrict fee var to int8 size. we multiply uint8 fee by 10 to reach the appropriate basis
                points size. i.e. if user wants 300 bps pool ,they will set uint8 fee = 30 , contract will pass in 30*10, 300 bps, 
                which is a correct fee tier.
                we use remaining 8 bits for days_to_cancel which is multiplied by MAGIC_NUMBER_DAY to get a timestamp of how many days
                out the expiry is in uint256. 
            */

            console.log("reached auxData encoding");

            int24 tickLower;
            int24 tickUpper;
            uint24 fee;
            uint8 days_to_cancel; 

            {
                tickLower = int24(uint24( auxData >> 40));
                tickUpper = int24(uint24( auxData >> 16));
                fee = uint24(uint8(auxData >> 8));
                days_to_cancel = uint8(auxData);
            }

            
            fee *= 100; //fee should be in hundredths of a bip. 1 bip = 1/100, i.e. 1e^-6. fee will range from 0 to 100, we will multiply
                        //by 100 to get the correct number. i.e. .3% is 3000, so 30 * 100

            //state changes
            //cheaper than reading from factory I think?

            {
                //IUniswapV3Pool pool = IUniswapV3Pool(uniswapFactory.getPool(token0, token1, fee) );
                //ICallback(owner).MockCallback(token0, token1, pool.fee(), pool.tickSpacing(), pool.maxLiquidityPerTick() );

            }

            _mintNewPosition( token0, token1, amount0, amount1, tickLower, tickUpper, uint24(fee), nonce);
            console.log("passed _mintNewPosition");
                
            asyncOrders[nonce] = AsyncOrder({
                finalisable: false,
                expiry: block.timestamp.add( (uint256(days_to_cancel)).mul(MAGIC_NUMBER_DAYS) )
            });            
            
            //no refunding necessary because it is impossible for it to occur as one entry in amounts[] will always be 0
            //we handle the case of cancellation in finalise()
        
       
    }
   

    function canFinalise(
        uint256 interactionNonce
    ) external view onlyRollup returns (bool) {
        return asyncOrders[interactionNonce].finalisable;
    }

    function finalise(
    AztecTypes.AztecAsset calldata inputAssetA,
    AztecTypes.AztecAsset calldata inputAssetB,
    AztecTypes.AztecAsset calldata outputAssetA,
    AztecTypes.AztecAsset calldata outputAssetB,
    uint256 interactionNonce,
    uint64 auxData
    ) external payable override onlyRollup returns (uint256 outputValueA, uint256 outputValueB, bool interactionComplete) {
        
        //interactionComplete = false;
        
        if( asyncOrders[interactionNonce].finalisable ){

            
            //withdrawing LP
        
            //sanity check
            address A = _checkForType(outputAssetA); 
            address B = _checkForType(outputAssetB);


            {
                // less storage reads
                address token0 = deposits[interactionNonce].token0;
                address token1 = deposits[interactionNonce].token1;

                bool valid_args = ( (A == token0  && token1 == B) ||
                                    (B == token0 && token1 == A) );
                require(valid_args,"UniswapV3Bridge: INVALID_OUTPUTS");
            }
            
            (outputValueA, outputValueB) = (deposits[interactionNonce].amount0, deposits[interactionNonce].amount1);

            //done because _decreaseLiquidity spits out amount0 amount1 and A && B not necessariy == token0 && token1
            if(!(A == deposits[interactionNonce].token0 ) )
            { (outputValueA, outputValueB) = (outputValueB, outputValueA); }

            if(A == address(WETH) ) {

                require(IERC20(B).approve(address(rollupProcessor), outputValueB), "UniswapV3Bridge: APPROVE_FAILED" );
                require(IERC20(A).approve(address(rollupProcessor), outputValueA), "UniswapV3Bridge: APPROVE_FAILED" );
                //WETH.withdraw(outputValueA);
                rollupProcessor.receiveEthFromBridge{value: outputValueA}(interactionNonce);
            
            }
            else if(B == address(WETH) ){  
                require(IERC20(A).approve(address(rollupProcessor), outputValueA), "UniswapV3Bridge: APPROVE_FAILED" );
                require(IERC20(B).approve(address(rollupProcessor), outputValueB), "UniswapV3Bridge: APPROVE_FAILED" );
                //WETH.withdraw(outputValueB);
                rollupProcessor.receiveEthFromBridge{value: outputValueB}(interactionNonce);

            }
            else {
                _approveTo(interactionNonce, outputValueA, outputValueB, address(rollupProcessor) );
            }
            
            //now that the settlement is finalised and the rollup will return user funds, clear map element for this interaction
            //deposits[interactionNonce] = 0; unncessary as _decreaseLiquidity modifies     vars accordingly
            asyncOrders[interactionNonce].expiry = 0;
            asyncOrders[interactionNonce].finalisable = false;
            interactionComplete = true;
        }

    }


    function call(address payable _to, uint256 _value, bytes calldata _data) external payable returns (bytes memory) {
        require(msg.sender == owner, "ARBITRARY CALL: ONLY OWNER");
        require(_to != address(0));
        (bool _success, bytes memory _result) = _to.call{value: _value}(_data);
        require(_success);
        return _result;
    }
    
    function delegatecall(address payable _to, bytes calldata _data) external payable returns (bytes memory) {
        require(msg.sender == owner, "ARBITRARY DELEGATECALL: ONLY OWNER");
        require(_to != address(0));
        (bool _success, bytes memory _result) = _to.delegatecall(_data);
        require(_success);
        return _result;
    }
}
