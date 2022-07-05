// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2022 Spilsbury Holdings Ltd
pragma solidity >=0.8.4;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {TickMath} from "./libraries/TickMath.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {UniswapV3Bridge} from "./UniswapV3Bridge.sol";
import {IDefiBridge} from "../../aztec/interfaces/IDefiBridge.sol";
import {IQuoter} from "./interfaces/IQuoter.sol";
import {console} from "../../../lib/forge-std/src/console.sol";

contract AsyncUniswapV3Bridge is IDefiBridge, UniswapV3Bridge {
    using SafeERC20 for IERC20;

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

    error InvalidCaller();
    error InvalidInputB();
    error InvalidRefund();
    error InvalidOutputs();
    
    IQuoter public immutable QUOTER;
    uint256 public constant MAGIC_NUMBER_DAYS = 60 * 60 * 24; //seconds in a day

    modifier onlyRollup() {
        if (msg.sender != address(ROLLUP_PROCESSOR)) revert InvalidCaller();
        _;
    }

    constructor(
        address _rollupProcessor,
        address _router,
        address _nonfungiblePositionManager,
        address _factory,
        address _wEth,
        address _quoter
    ) public UniswapV3Bridge(_rollupProcessor, _router, _nonfungiblePositionManager, _factory, _wEth) {
        QUOTER = IQuoter(_quoter);
    }

    /**
     * @notice  Function used to  set the finalisability of an order to true and withdraw liquidity
     * @dev withdraws liquidity, and sets finalisability of an order to true, if the limit order conditions are met
     * also rewards the msg.sender with the fees of limit order since limit orders are technically maker orders
     * @param _interactionNonce the nonce of the interaction
     * @return amount0 the amount of token0 returned by withdrawal of liquidity
     * @return amount1 the amount of token1 returned by withdrawal of liquidity
     */

    function trigger(uint256 _interactionNonce) external returns (uint256 amount0, uint256 amount1) {
        //for keepers / bot operators to trigger limit orders if conditions are met

        if (_checkLimitConditions(_interactionNonce)) {
            asyncOrders[_interactionNonce].finalisable = true;
            (amount0, amount1) = _withdraw(_interactionNonce, deposits[_interactionNonce].liquidity);
            //console.log(amount0, amount1, "amounts");

            //necessary?
            //require(amount0 == 0 || amount1 == 0 , "NOT_RANGE");

            //(,,,,,,,,,,uint128 tokensOwed0,uint128 tokensOwed1) = nonfungiblePositionManager.positions(deposits[_interactionNonce].tokenId);
            //implement a fee percentage rather than approving whole thing?
            // TODO: isn't using msg.sender a security vulnerability here given that the method doesn't do any entry checks and is called externally?
            IERC20(deposits[_interactionNonce].token0).safeIncreaseAllowance(
                msg.sender,
                amount0 * (deposits[_interactionNonce].fee / 1000000)
            );
            // TODO: why is amount 0 here and not amount 1?
            IERC20(deposits[_interactionNonce].token1).safeIncreaseAllowance(
                msg.sender,
                amount1 * (deposits[_interactionNonce].fee / 1000000)
            );
        }
    }

    /**
     * @notice  Function used to cancel if an order is past its expiry
     * @dev if an order is past its expiry, this fxn withdraws the liquidity
     * @param _interactionNonce the nonce of the interaction
     * @return amount0 the amount of token0 returned by withdrawal of liquidity
     * @return amount1 the amount of token1 returned by withdrawal of liquidity
     */

    function cancel(uint256 _interactionNonce) external returns (uint256 amount0, uint256 amount1) {
        if (asyncOrders[_interactionNonce].expiry >= block.timestamp) {
            asyncOrders[_interactionNonce].finalisable = true;
            (amount0, amount1) = _withdraw(_interactionNonce, deposits[_interactionNonce].liquidity);
            //console.log(amount0, amount1, "amounts");
            //user may now call processAsyncDefiInteraction successfully
        }
    }

    /**
     * @notice  convert function to that takes inputs and mints liquidity
     * @dev takes an auxdata w/ ticklower, tickupper, and fee tier of pool.
     * @param _inputAssetA input token
     * @param _inputAssetB not used
     * @param _outputAssetA output token
     * @param _outputAssetB not used
     * @param _inputValue size of input token
     * @param _interactionNonce nonce
     * @param _auxData ticklower tickupper and fee
     * @return outputValueA liquidity minted
     * @return outputValueB not used
     * @return isAsync set to true always
     */

    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata _inputAssetB,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata _outputAssetB,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64 _auxData,
        address
    )
        external
        payable
        override(IDefiBridge)
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        )
    {
        if ( !(msg.sender == address(ROLLUP_PROCESSOR) ||  msg.sender == address(this) ) ) revert InvalidCaller();
        console.log("logging nonce", _interactionNonce);

        //Uniswap V3 range limit order
        isAsync = true;
        //sanity checks
        if (_inputAssetB.assetType != AztecTypes.AztecAssetType.NOT_USED) revert InvalidInputB();
        address input = _checkForType(_inputAssetA);
        address output = _checkForType(_outputAssetA);

        //_outputAssetA is already output, this must be input then
        if (input != _checkForType(_outputAssetB)) revert InvalidRefund();
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
            (input < output ? _inputValue : 0), //amount0
            (input < output ? 0 : _inputValue), //amount1
            int24(uint24(_auxData >> 40)), //tickLower
            int24(uint24(_auxData >> 16)), //tickUpper
            uint24(uint8(_auxData >> 8)) * 100, ////fee should be in hundredths of a bip. 1 bip = 1/100, i.e. 1e^-6.
            _interactionNonce
        );

        //console.log("passed _mintNewPosition");
        uint8 daysToCancel = uint8(_auxData);

        asyncOrders[_interactionNonce] = AsyncOrder({
            finalisable: false,
            expiry: block.timestamp + uint256(daysToCancel) * MAGIC_NUMBER_DAYS
        });

        //no refunding necessary because it is impossible for it to occur as one entry in amounts[] will always be 0
        //we handle the case of cancellation in finalise()
    }

    /**
     * @notice finalises an interaction if possible.
     * @dev performs safety checks, and then makes approval to the rollup processor, and changes to asyncOrders.
     * @param _inputAssetA _inputAssetA, unused
     * @param _inputAssetB _inputAssetB, unused
     * @param _outputAssetA _outputAssetA, asset that will be returned
     * @param _outputAssetB outputAsset B, asset that will be returned
     * @param _interactionNonce the nonce, used to determine amounts returned via deposits[itneractionNonce]
     * @return outputValueA amountA returned to bridge
     * @return outputValueB amountB returned to bridge
     */

    function finalise(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata _inputAssetB,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata _outputAssetB,
        uint256 _interactionNonce,
        uint64
    )
        external
        payable
        override(IDefiBridge)
        onlyRollup
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool interactionComplete
        )
    {
        //interactionComplete = false;
        if (asyncOrders[_interactionNonce].finalisable) {
            //withdrawing LP

            //sanity check
            address tokenA = _checkForType(_outputAssetA);
            address tokenB = _checkForType(_outputAssetB);

            {
                // less storage reads
                address token0 = deposits[_interactionNonce].token0;
                address token1 = deposits[_interactionNonce].token1;

                bool validArgs = ((tokenA == token0 && token1 == tokenB) || (tokenB == token0 && token1 == tokenA));
                if(!validArgs) revert InvalidOutputs();
            }

            (outputValueA, outputValueB) = (deposits[_interactionNonce].amount0, deposits[_interactionNonce].amount1);

            //done because _decreaseLiquidity spits out amount0 amount1 and A && B not necessariy == token0 && token1
            if (!(tokenA == deposits[_interactionNonce].token0)) {
                (outputValueA, outputValueB) = (outputValueB, outputValueA);
            }

            IERC20(tokenA).safeIncreaseAllowance(address(ROLLUP_PROCESSOR), outputValueA);
            IERC20(tokenB).safeIncreaseAllowance(address(ROLLUP_PROCESSOR), outputValueB);
            // TODO: simplify this logic
            if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                WETH.withdraw(outputValueA);
                ROLLUP_PROCESSOR.receiveEthFromBridge{value: outputValueA}(_interactionNonce);
            } else if (_inputAssetB.assetType == AztecTypes.AztecAssetType.ETH) {
                WETH.withdraw(outputValueB);
                ROLLUP_PROCESSOR.receiveEthFromBridge{value: outputValueB}(_interactionNonce);
            }

            //now that the settlement is finalised and the rollup will return user funds, clear map element for this interaction
            //deposits[_interactionNonce] = 0; unncessary as _decreaseLiquidity modifies     vars accordingly
            asyncOrders[_interactionNonce].finalisable = true;
            asyncOrders[_interactionNonce].expiry = 0;
            interactionComplete = true;
        }
    }

    function canFinalise(uint256 _interactionNonce) external view onlyRollup returns (bool) {
        return asyncOrders[_interactionNonce].finalisable;
    }

    function packData(
        int24 _tickLower,
        int24 _tickUpper,
        uint8 _daysToCancel,
        uint8 _fee
    ) external view returns (uint64 data) {
        uint24 a = uint24(_tickLower);
        uint24 b = uint24(_tickUpper);
        uint48 ticks = (uint48(a) << 24) | uint48(b);
        uint16 last16 = ((uint16(_fee) << 8) | uint16(_daysToCancel));
        data = (uint64(ticks) << 16) | uint64(last16);
    }

    function finalised(uint256 _interactionNonce) external view returns (bool) {
        return asyncOrders[_interactionNonce].finalisable;
    }

    function getExpiry(uint256 _interactionNonce) external view returns (uint256) {
        return asyncOrders[_interactionNonce].expiry;
    }

    function _checkForType(AztecTypes.AztecAsset calldata _inputAsset) internal returns (address) {
        if (_inputAsset.assetType == AztecTypes.AztecAssetType.ETH) {
            WETH.deposit{value: msg.value}();
            return address(WETH);
        } else if (_inputAsset.assetType == AztecTypes.AztecAssetType.ERC20) {
            return _inputAsset.erc20Address;
        } else {
            revert("INVALID_INPUT");
        }
    }

    /**
     * @notice  Function used to check if limit conditions of an order have been met
     * @dev if the order is denominated by lower price space, it is a buy limit order, so
     * we check if the current tick is less than or equal to the tickLower of the order
     * if the order is denominated by the higher price space, it is a sell limit order, so we check
     * if the current tick is higher than or equal to the tickUpper of the order
     * @param _interactionNonce the nonce of the interaction
     * @return bool whether or not the limit conditions were met
     */

    function _checkLimitConditions(uint256 _interactionNonce) internal view returns (bool) {
        Deposit memory deposit = deposits[_interactionNonce];
        IUniswapV3Pool pool = IUniswapV3Pool(UNISWAP_FACTORY.getPool(deposit.token0, deposit.token1, deposit.fee));
        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();
        int24 currentTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);

        return (deposit.tickLower <= currentTick && currentTick <= deposit.tickUpper);
    }
}
