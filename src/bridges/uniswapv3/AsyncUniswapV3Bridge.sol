// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;

import {AztecTypes} from "../../aztec/AztecTypes.sol";
import {TickMath} from "./libraries/TickMath.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IUniswapV3Pool.sol";
import "./UniswapV3Bridge.sol";
import "../../interfaces/IDefiBridge.sol";
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

    constructor(
        address _rollupProcessor,
        address _router,
        address _nonfungiblePositionManager,
        address _factory,
        address _WETH,
        address _quoter
    ) public UniswapV3Bridge(_rollupProcessor, _router, _nonfungiblePositionManager, _factory, _WETH) {
        quoter = IQuoter(_quoter);
    }

    modifier onlyRollup() {
        require(msg.sender == address(rollupProcessor), "INVALID_CALLER");
        _;
    }

    function packData(
        int24 tickLower,
        int24 tickUpper,
        uint8 days_to_cancel,
        uint8 fee
    ) external view returns (uint64 data) {
        uint24 a = uint24(tickLower);
        uint24 b = uint24(tickUpper);
        uint48 ticks = (uint48(a) << 24) | uint48(b);
        uint8 days_to_cancel = 1;
        uint16 last16 = ((uint16(fee) << 8) | uint16(days_to_cancel));
        data = (uint64(ticks) << 16) | uint64(last16);
    }

    function finalised(uint256 interactionNonce) external view returns (bool) {
        return asyncOrders[interactionNonce].finalisable;
    }

    function getExpiry(uint256 interactionNonce) external view returns (uint256) {
        return asyncOrders[interactionNonce].expiry;
    }

    /**
     * @notice  Function used to check if limit conditions of an order have been met
     * @dev if the order is denominated by lower price space, it is a buy limit order, so
     * we check if the current tick is less than or equal to the tickLower of the order
     * if the order is denominated by the higher price space, it is a sell limit order, so we check
     * if the current tick is higher than or equal to the tickUpper of the order
     * @param interactionNonce the nonce of the interaction
     * @return bool whether or not the limit conditions were met
     */

    function _checkLimitConditions(uint256 interactionNonce) internal view returns (bool) {
        Deposit memory deposit = deposits[interactionNonce];
        IUniswapV3Pool pool = IUniswapV3Pool(uniswapFactory.getPool(deposit.token0, deposit.token1, deposit.fee));
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        int24 currentTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        return (deposit.tickLower <= currentTick && currentTick <= deposit.tickUpper);
    }

    /**
     * @notice  Function used to  set the finalisability of an order to true and withdraw liquidity
     * @dev withdraws liquidity, and sets finalisability of an order to true, if the limit order conditions are met
     * also rewards the msg.sender with the fees of limit order since limit orders are technically maker orders
     * @param interactionNonce the nonce of the interaction
     * @return amount0 the amount of token0 returned by withdrawal of liquidity
     * @return amount1 the amount of token1 returned by withdrawal of liquidity
     */

    function trigger(uint256 interactionNonce) external returns (uint256 amount0, uint256 amount1) {
        //for keepers / bot operators to trigger limit orders if conditions are met

        if (_checkLimitConditions(interactionNonce)) {
            asyncOrders[interactionNonce].finalisable = true;
            (amount0, amount1) = _withdraw(interactionNonce, deposits[interactionNonce].liquidity);
            //console.log(amount0, amount1, "amounts");

            //necessary?
            //require(amount0 == 0 || amount1 == 0 , "NOT_RANGE");

            //(,,,,,,,,,,uint128 tokensOwed0,uint128 tokensOwed1) = nonfungiblePositionManager.positions(deposits[interactionNonce].tokenId);
            //implement a fee percentage rather than approving whole thing?
            ERC20NoReturnApprove(
                deposits[interactionNonce].token0,
                address(msg.sender),
                amount0 * (deposits[interactionNonce].fee / 1000000)
            );
            ERC20NoReturnApprove(
                deposits[interactionNonce].token1,
                address(msg.sender),
                amount0 * (deposits[interactionNonce].fee / 1000000)
            );
        }
    }

    /**
     * @notice  Function used to cancel if an order is past its expiry
     * @dev if an order is past its expiry, this fxn withdraws the liquidity
     * @param interactionNonce the nonce of the interaction
     * @return amount0 the amount of token0 returned by withdrawal of liquidity
     * @return amount1 the amount of token1 returned by withdrawal of liquidity
     */

    function cancel(uint256 interactionNonce) external returns (uint256 amount0, uint256 amount1) {
        if (asyncOrders[interactionNonce].expiry >= block.timestamp) {
            asyncOrders[interactionNonce].finalisable = true;
            (amount0, amount1) = _withdraw(interactionNonce, deposits[interactionNonce].liquidity);
            //console.log(amount0, amount1, "amounts");
            //user may now call processAsyncDefiInteraction successfully
        }
    }

    function _checkForType(AztecTypes.AztecAsset calldata inputAsset) internal returns (address) {
        if (inputAsset.assetType == AztecTypes.AztecAssetType.ETH) {
            WETH.deposit{value: msg.value}();
            return address(WETH);
        } else if (inputAsset.assetType == AztecTypes.AztecAssetType.ERC20) {
            return inputAsset.erc20Address;
        } else {
            revert("INVALID_INPUT");
        }
    }

    /**
     * @notice  convert function to that takes inputs and mints liquidity
     * @dev takes an auxdata w/ ticklower, tickupper, and fee tier of pool.
     * @param inputAssetA input token
     * @param inputAssetB not used
     * @param outputAssetA output token
     * @param outputAssetB not used
     * @param inputValue size of input token
     * @param interactionNonce nonce
     * @param auxData ticklower tickupper and fee
     * @return outputValueA liquidity minted
     * @return outputValueB not used
     * @return isAsync set to true always
     */

    function convert(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata inputAssetB,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata outputAssetB,
        uint256 inputValue,
        uint256 interactionNonce,
        uint64 auxData,
        address
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
        require(msg.sender == address(rollupProcessor), "INVALID_CALLER");

        //Uniswap V3 range limit order
        isAsync = true;
        //sanity checks
        require(inputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED, "INCORRECT_INPUTB");
        address input = _checkForType(inputAssetA);
        address output = _checkForType(outputAssetA);

        //outputAssetA is already output, this must be input then
        require(input == _checkForType(outputAssetB), "INVALID_REFUND");

        //console.log("passed require checks");

        //address pool = uniswapFactory.getPool(input_address,output_address,fee);
        //require(pool != address(0), "NONEXISTENT_POOL");

        /* 
                to fit all data into 64 bits, we constrict fee var to int8 size. we multiply uint8 fee by 10 to reach the appropriate basis
                points size. i.e. if user wants 300 bps pool ,they will set uint8 fee = 30 , contract will pass in 30*10, 300 bps, 
                which is a correct fee tier.
                we use remaining 8 bits for days_to_cancel which is multiplied by MAGIC_NUMBER_DAY to get a timestamp of how many days
                out the expiry is in uint256. 
            */

        //console.log("reached auxData encoding");

        //fee should be in hundredths of a bip. 1 bip = 1/100, i.e. 1e^-6. fee will range from 0 to 100, we will multiply
        //by 100 to get the correct number. i.e. .3% is 3000, so 30 * 100

        //state changes

        _mintNewPosition(
            (input < output ? input : output), //token0
            (input < output ? output : input), //token1
            (input < output ? inputValue : 0), //amount0
            (input < output ? 0 : inputValue), //amount1
            int24(uint24(auxData >> 40)), //tickLower
            int24(uint24(auxData >> 16)), //tickUpper
            uint24(uint8(auxData >> 8)) * 100, ////fee should be in hundredths of a bip. 1 bip = 1/100, i.e. 1e^-6.
            interactionNonce
        );

        //console.log("passed _mintNewPosition");
        uint8 days_to_cancel = uint8(auxData);

        asyncOrders[interactionNonce] = AsyncOrder({
            finalisable: false,
            expiry: block.timestamp.add((uint256(days_to_cancel)).mul(MAGIC_NUMBER_DAYS))
        });

        //no refunding necessary because it is impossible for it to occur as one entry in amounts[] will always be 0
        //we handle the case of cancellation in finalise()
    }

    function canFinalise(uint256 interactionNonce) external view onlyRollup returns (bool) {
        return asyncOrders[interactionNonce].finalisable;
    }

    /**
     * @notice finalises an interaction if possible.
     * @dev performs safety checks, and then makes approval to the rollup processor, and changes to asyncOrders.
     * @param inputAssetA inputAssetA, unused
     * @param inputAssetB inputAssetB, unused
     * @param outputAssetA outputAssetA, asset that will be returned
     * @param outputAssetB outputAsset B, asset that will be returned
     * @param interactionNonce the nonce, used to determine amounts returned via deposits[itneractionNonce]
     * @param auxData unused
     * @return outputValueA amountA returned to bridge
     * @return outputValueB amountB returned to bridge
     */

    function finalise(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata inputAssetB,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata outputAssetB,
        uint256 interactionNonce,
        uint64 auxData
    )
        external
        payable
        override
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool interactionComplete
        )
    {
        //interactionComplete = false;

        if (asyncOrders[interactionNonce].finalisable) {
            //withdrawing LP

            //sanity check
            address A = _checkForType(outputAssetA);
            address B = _checkForType(outputAssetB);

            {
                // less storage reads
                address token0 = deposits[interactionNonce].token0;
                address token1 = deposits[interactionNonce].token1;

                bool valid_args = ((A == token0 && token1 == B) || (B == token0 && token1 == A));
                require(valid_args, "INVALID_OUTPUTS");
            }

            (outputValueA, outputValueB) = (deposits[interactionNonce].amount0, deposits[interactionNonce].amount1);

            //done because _decreaseLiquidity spits out amount0 amount1 and A && B not necessariy == token0 && token1
            if (!(A == deposits[interactionNonce].token0)) {
                (outputValueA, outputValueB) = (outputValueB, outputValueA);
            }

            if (inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                ERC20NoReturnApprove(B, address(rollupProcessor), outputValueB);
                TransferHelper.safeApprove(A, address(rollupProcessor), outputValueA);
                WETH.withdraw(outputValueA);
                rollupProcessor.receiveEthFromBridge{value: outputValueA}(interactionNonce);
            } else if (inputAssetB.assetType == AztecTypes.AztecAssetType.ETH) {
                TransferHelper.safeApprove(B, address(rollupProcessor), outputValueB);
                ERC20NoReturnApprove(A, address(rollupProcessor), outputValueA);
                WETH.withdraw(outputValueB);
                rollupProcessor.receiveEthFromBridge{value: outputValueB}(interactionNonce);
            } else {
                ERC20NoReturnApprove(B, address(rollupProcessor), outputValueB);
                ERC20NoReturnApprove(A, address(rollupProcessor), outputValueA);
            }

            //now that the settlement is finalised and the rollup will return user funds, clear map element for this interaction
            //deposits[interactionNonce] = 0; unncessary as _decreaseLiquidity modifies     vars accordingly
            asyncOrders[interactionNonce].finalisable = true;
            asyncOrders[interactionNonce].expiry = 0;
            interactionComplete = true;
        }
    }
}
