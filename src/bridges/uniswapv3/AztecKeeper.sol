// SPDX-License-Identifier: MIT
pragma solidity >=0.6.10 <=0.8.10;

import "./interfaces/KeeperCompatibleInterface.sol";
import {TickMath} from "./libraries/TickMath.sol";
interface IUniswapV3Factory {

    function getPool(
        address tokenA,
        address tokenB,
        uint24 fee
    ) external view returns (address pool);

}

interface IUniswapV3Pool {


    function slot0(
  ) external view returns (uint160 sqrtPriceX96, int24 tick, uint16 observationIndex, uint16 observationCardinality, uint16 observationCardinalityNext, uint8 feeProtocol, bool unlocked);

}

interface IDefiBridge {


    function getDeposit(uint256 interactionNonce) external view returns (
        uint256 ,
        uint128 , 
        uint256 ,
        uint256 ,
        int24 ,
        int24 ,
        uint24 ,
        address , 
        address );
}

interface IRollupProcessor {
    function processAsyncDeFiInteraction(uint256 interactionNonce) external;
}

contract AztecKeeper is KeeperCompatibleInterface {
    /**
    * Public counter variable
    */
    uint public counter;

    /**
    * Use an interval in seconds and a timestamp to slow execution of Upkeep
    */

    uint public immutable interval;
    uint public lastTimeStamp;

    IUniswapV3Factory private immutable factory;
    IDefiBridge private immutable bridge;
    IRollupProcessor private immutable rollupProcessor;


    constructor(uint updateInterval, address _factory, address _rollupProcessor, address _bridge) {
      
      interval = updateInterval;
      lastTimeStamp = block.timestamp;
      factory = IUniswapV3Factory(_factory);
      rollupProcessor = IRollupProcessor(_rollupProcessor);
      bridge = IDefiBridge(_bridge);
      counter = 0;
    
    }

    function checkUpkeep(bytes calldata checkData ) external view override returns (bool upkeepNeeded, bytes memory performData ) {
        // We don't use the checkData in this example. The checkData is defined when the Upkeep was registered.
        uint256[] memory interactions = abi.decode(checkData, (uint256[] ) );
        uint256 length = interactions.length;
        uint256[] memory finalisable = new uint256[](length); 

        uint finalisableCtr = 0;
        IUniswapV3Pool pool;
        
        for(uint i = 0; i < length; i++){
            
            (,
            , 
            uint256 amount0,
            uint256 amount1,
            int24 tickLower,
            int24 tickUpper,
            uint24 fee,
            address token0, 
            address token1 
            ) = bridge.getDeposit(interactions[i]);
            pool = IUniswapV3Pool(factory.getPool(token0, token1, fee));
            (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
            int24 currentTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

            if(tickLower <= currentTick && currentTick <= tickUpper ){
                finalisable[finalisableCtr] = interactions[i];
                finalisableCtr++;
            }
        }
        performData = abi.encode(finalisable);
        upkeepNeeded = (block.timestamp - lastTimeStamp) > interval && performData.length != 0;
    }

    function performUpkeep(bytes calldata performData) external override {
        lastTimeStamp = block.timestamp;
        counter = counter + 1;
        uint256[] memory finalisable =  abi.decode(performData , (uint256[] ) );
        uint256 length = finalisable.length;
        for(uint i = 0; i < length; i++){
            if(finalisable[i] != 0) {
                rollupProcessor.processAsyncDeFiInteraction(finalisable[i]);
            }
        }
            
    }   
}