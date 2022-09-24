// SPDX-License-Identifier: MIT
pragma solidity >=0.8.4;

import {KeeperCompatibleInterface} from "../../interfaces/uniswapv3/KeeperCompatibleInterface.sol";
import {TickMath} from "../../libraries/uniswapv3/TickMath.sol";
import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";
import {IUniswapV3Pool} from "../../interfaces/uniswapv3/IUniswapV3Pool.sol";
import {IUniswapV3Factory} from "../../interfaces/uniswapv3/IUniswapV3Factory.sol";

interface IBridge {
    function getDeposit(uint256 _interactionNonce)
        external
        view
        returns (
            uint256,
            uint128,
            uint256,
            uint256,
            int24,
            int24,
            uint24,
            address,
            address
        );
}

contract AztecKeeper is KeeperCompatibleInterface {
    /**
     * Public counter variable
     */
    uint256 public counter;

    /**
     * Use an interval in seconds and a timestamp to slow execution of Upkeep
     */

    uint256 public immutable INTERVAL;
    uint256 public lastTimeStamp;

    IUniswapV3Factory private immutable FACTORY;
    IBridge private immutable BRIDGE;
    IRollupProcessor private immutable ROLLUP_PROCESSOR;

    constructor(
        uint256 _updateInterval,
        address _factory,
        address _rollupProcessor,
        address _bridge
    ) {
        INTERVAL = _updateInterval;
        lastTimeStamp = block.timestamp;
        FACTORY = IUniswapV3Factory(_factory);
        ROLLUP_PROCESSOR = IRollupProcessor(_rollupProcessor);
        BRIDGE = IBridge(_bridge);
        counter = 0;
    }

    function performUpkeep(bytes calldata _performData) external override(KeeperCompatibleInterface) {
        lastTimeStamp = block.timestamp;
        counter = counter + 1;
        uint256[] memory finalisable = abi.decode(_performData, (uint256[]));
        uint256 length = finalisable.length;
        for (uint256 i = 0; i < length; i++) {
            if (finalisable[i] != 0) {
                bytes memory payload = abi.encodeWithSignature("trigger(uint256)", finalisable[i]);
                (, bytes memory data) = address(BRIDGE).call(payload);
                //not used, uncomment to use
                //(uint256 out0, uint256 out1) = abi.decode(data, (uint256, uint256));
                ROLLUP_PROCESSOR.processAsyncDefiInteraction(finalisable[i]);
            }
        }
    }

    function checkUpkeep(bytes calldata _checkData)
        external
        view
        override(KeeperCompatibleInterface)
        returns (bool upkeepNeeded, bytes memory performData)
    {
        // We don't use the checkData in this example. The checkData is defined when the Upkeep was registered.
        uint256[] memory interactions = abi.decode(_checkData, (uint256[]));
        uint256 length = interactions.length;
        uint256[] memory finalisable = new uint256[](length);

        uint256 finalisableCtr = 0;
        IUniswapV3Pool pool;

        for (uint256 i = 0; i < length; i++) {
            (
                ,
                ,
                uint256 amount0,
                uint256 amount1,
                int24 tickLower,
                int24 tickUpper,
                uint24 fee,
                address token0,
                address token1
            ) = BRIDGE.getDeposit(interactions[i]);
            pool = IUniswapV3Pool(FACTORY.getPool(token0, token1, fee));
            (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
            int24 currentTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

            if (tickLower <= currentTick && currentTick <= tickUpper) {
                finalisable[finalisableCtr] = interactions[i];
                finalisableCtr++;
            }
        }
        performData = abi.encode(finalisable);
        upkeepNeeded = (block.timestamp - lastTimeStamp) > INTERVAL && performData.length != 0;
    }
}
