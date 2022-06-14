// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import {SafeMath} from '@openzeppelin/contracts/utils/math/SafeMath.sol';
import {IDefiBridge} from '../../interfaces/IDefiBridge.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {AztecTypes} from '../../aztec/AztecTypes.sol';
import {TickMath} from "../../bridges/uniswapv3/libraries/TickMath.sol";
import {FullMath} from "../../bridges/uniswapv3/libraries/FullMath.sol";
import {ISwapRouter} from '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import {IQuoter} from '@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol';
import {IUniswapV3Factory} from"@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {IRollupProcessor} from "../../interfaces/IRollupProcessor.sol";
import {IStethPriceFeed} from './interfaces/IStethPriceFeed.sol';
import {ISupplyCapIssuanceHook} from './interfaces/ISupplyCapIssuanceHook.sol';
import {IAaveLeverageModule} from './interfaces/IAaveLeverageModule.sol';
import {ICurvePool} from './interfaces/ICurvePool.sol';
import {IWeth} from './interfaces/IWeth.sol';
import {IExchangeIssue} from './interfaces/IExchangeIssue.sol';
import {ISetToken} from './interfaces/ISetToken.sol';

import '../../../lib/forge-std/src/Test.sol';

/** 
* @title icETH Bridge
* @dev A smart contract responsible for buying and selling icETH with ETH etther through selling/buying from 
* a DEX or by issuing/redeeming icEth set tokens.
*/

contract IndexBridgeContract is IDefiBridge {
    using SafeMath for uint256;

    address immutable ROLLUP_PROCESSOR;
    address immutable EXISSUE = 0xB7cc88A13586D862B97a677990de14A122b74598;
    address immutable CURVE = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address immutable WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address immutable STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address immutable ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address immutable ICETH = 0x7C07F7aBe10CE8e33DC6C5aD68FE033085256A84;
    address immutable STETH_PRICE_FEED = 0xAb55Bf4DfBf469ebfe082b7872557D1F87692Fe6;
    address immutable AAVE_LEVERAGE_MODULE = 0x251Bd1D42Df1f153D86a5BA2305FaADE4D5f51DC;
    address immutable ICETH_SUPPLY_CAP = 0x2622c4BB67992356B3826b5034bB2C7e949ab12B; 

    address immutable UNIV3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address immutable UNIV3_QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address immutable UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984; 
    uint24 immutable uniFee = 3000;

    constructor(address _rollupProcessor) public {
        ROLLUP_PROCESSOR = _rollupProcessor;
    }

    fallback() external payable {}

    /**
    * @notice Function that swaps between icETH and ETH.
    * @dev The flow of this functions is based on the type of input and output assets.
    *
    * @param inputAssetA - ETH to buy/issue icETH, icETH to sell/redeem icETH.
    * @param outputAssetA - icETH to buy/issue icETH, ETH to sell/redeem icETH. 
    * @param outputAssetB - ETH to buy/issue icETH, empty to sell/redeem icETH. 
    * @param totalInputValue - Total amount of ETH/icETH to be swapped for icETH/ETH
    * @param interactionNonce - Globablly unique identifier for this bridge call
    * @param auxData - Used to specific maximal difference between expected
    * amounts recevied based on Oracle data and the actual amount recevied. 
    * @return outputValueA - Amount of icETH received when buying/issuing, Amount of ETH 
    * received when selling/redeeming.
    * @return outputValueB - Amount of ETH returned when issuing icETH. A portion of ETH 
    * is always returned when issuing icETH since the issuing function in ExchangeIssuance
    * requires an exact output amount rather than input. 
    */

    function convert(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata ,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata outputAssetB,
        uint256 totalInputValue,
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
        isAsync = false;

        // // ### INITIALIZATION AND SANITY CHECKS
        require(msg.sender == ROLLUP_PROCESSOR, 'ExampleBridge: INVALID_CALLER');

        if ( // To buy/issue
            inputAssetA.assetType == AztecTypes.AztecAssetType.ETH &&
            outputAssetA.erc20Address == ICETH &&
            outputAssetB.assetType == AztecTypes.AztecAssetType.ETH
            ) 
        {

            (outputValueA, outputValueB) = getIcEth(totalInputValue, auxData, interactionNonce);

        } else if (  // To sell/redeem  
            inputAssetA.erc20Address == ICETH &&
            outputAssetA.assetType == AztecTypes.AztecAssetType.ETH
            ) 
        {

            outputValueA = getEth(totalInputValue, auxData, interactionNonce);

        }
    }

    // @dev This function always reverts since this contract has not async flow.
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
        returns (
            uint256,
            uint256,
            bool
        )
    {
        require(false);
    }

    /**
    * @dev This function either redeems icETH for ETH or sells icETH for ETH on univ3 depending
    * on the expected eth returned.
    *
    * @param totalInputValue - Total amount of icETH to be swapped/redeemed for ETH
    * @param interactionNonce - Globablly unique identifier for this bridge call
    * @param auxData - Used to specific maximal difference between expected
    * amounts recevied based on Oracle data and the actual amount recevied. 
    * @return outputValueA - Amount of ETH to return to the Rollupprocessor
    */

    function getEth(
        uint256 totalInputValue,
        uint64 auxData,
        uint256 interactionNonce
    ) 
        internal 
        returns (uint256 outputValueA) 
    {

        // Creating a SwapData structure used to specify a path in a DEX in the ExchangeIssuance contract
        uint24[] memory fee;
        address[] memory pathToEth = new address[](2); 
        pathToEth[0] = STETH;
        pathToEth[1] = ETH;

        IExchangeIssue.SwapData memory  redeemData; 
        redeemData = IExchangeIssue.SwapData(
            pathToEth, 
            fee,
            CURVE, 
            IExchangeIssue.Exchange.Curve
        );

        // Getting a quote of how much Eth can be aquired through a icETH->ETH swap on univ3
        bytes memory path = abi.encodePacked(ICETH, uniFee);
        path = abi.encodePacked(path, WETH);
        uint256 ethFromDex = IQuoter(UNIV3_QUOTER).quoteExactInput(path, totalInputValue);

        //  Getting a quote of how much Eth can be aquired by redeeming icETH->ETH through the ExchangeIssuance contract
        uint256 ethFromEx  = IExchangeIssue(EXISSUE).getRedeemExactSet(
            ISetToken(ICETH), 
            totalInputValue, 
            redeemData, 
            redeemData
        );

        uint256 minAmountOut;  
        if (ethFromEx > 1e6 &&
            ethFromEx - 1e6 > ethFromDex
            ) 
        { // ~1e6 is the difference in gas.

            // Cheaper to issue
            console2.log('Redeem Cheaper');

            /* Calculate minimum acceptable received eth based on underlyin assets(STETH)
            according to lido's oracle of icETH/ETH pool and the cost of a flashloan to
            settle the WETH debt.
            */
            
            minAmountOut = getEthFromRedeem(totalInputValue).mul(auxData).div(1e18);
            ISetToken(ICETH).approve(address(EXISSUE), totalInputValue);
    
            // Redeem icETH for eth
            IExchangeIssue(EXISSUE).redeemExactSetForETH(
                ISetToken(ICETH),
                totalInputValue,
                minAmountOut,
                redeemData,
                redeemData
            );

            outputValueA = address(this).balance;
            IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(interactionNonce);

        } else {
            // Cheaper to buy
            console2.log('Buying Cheaper');

            // Using univ3 TWAP Oracle to get a lower bound on returned ETH.
            minAmountOut = getAmountBasedOnTwap(uint128(totalInputValue), ICETH, WETH).mul(auxData).div(1e18);
            
            IERC20(ICETH).approve(UNIV3_ROUTER, totalInputValue);
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: ICETH,
                tokenOut: WETH,
                fee: uniFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: totalInputValue,
                amountOutMinimum: minAmountOut, 
                sqrtPriceLimitX96: 0
            });

            outputValueA = ISwapRouter(UNIV3_ROUTER).exactInputSingle(params);
            uint256 wethBalance = IWeth(WETH).balanceOf(address(this));

            IWeth(WETH).withdraw(outputValueA);
            IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueA}(interactionNonce);
        }
    }

    /**
    * @dev This function either issues icETH  or buys icETH with ETH on univ3 depending
    * on the expected icETH returned.
    *
    * @param totalInputValue - Total amount of icETH to be swapped/redeem for ETH
    * @param interactionNonce - Globablly unique identifier for this bridge call
    * @param auxData - Used to specific maximal difference between expected
    * amounts recevied based on Oracle data and the actual amount recevied. 
    * @return outputValueA - Amount of icETH to return to the Rollupprocessor
    */

    function getIcEth(
        uint256 totalInputValue,
        uint64 auxData,
        uint256 interactionNonce
    ) 
        internal 
        returns (uint256 outputValueA, uint256 outputValueB) 
    {

        IExchangeIssue.SwapData memory issueData; 
        uint256 issueCostOfTokens;
        bool issueOpen;

        {
        // Creating a SwapData structure used specify path in DEX in the ExchangeIssuance contract
            uint24[] memory fee;
            address[] memory pathToSt = new address[](2);
            pathToSt[0] = ETH;
            pathToSt[1] = STETH;
            issueData = IExchangeIssue.SwapData(
                pathToSt, fee, CURVE, IExchangeIssue.Exchange.Curve);

        // Getting a quote of how much icEth can be aquired through a eth->icEth swap on univ3
            bytes memory path = abi.encodePacked(WETH, uniFee);
            path = abi.encodePacked(path, address(ICETH));
            uint256 tokensFromDex = IQuoter(UNIV3_QUOTER).quoteExactInput(path, totalInputValue);

        // Get eth needed to get the same amount of icETH through ExchangeIssuance
            issueCostOfTokens = IExchangeIssue(EXISSUE).getIssueExactSet(
                ISetToken(ICETH),
                tokensFromDex,
                issueData,
                issueData
            );

        // Check if we are going over the supply cap of icETH, use DEX if we are.
            uint256 currentSupply = IERC20(ICETH).totalSupply();
            uint256 maxSupply = ISupplyCapIssuanceHook(ICETH_SUPPLY_CAP).supplyCap();
            issueOpen = (currentSupply + tokensFromDex < maxSupply) ? true : false; 

        }


        if (issueCostOfTokens > 1e6 && 
            (issueCostOfTokens - 1e6) < totalInputValue && 
            issueOpen
            ) 
        { //Accounting for gas difference ~ 1e6 in difference. 

            // Cheaper to issue
            console2.log('Issuing Cheaper');

            (outputValueA, outputValueB) = issueIcEth(totalInputValue, auxData, issueData);

            ISetToken(ICETH).approve(ROLLUP_PROCESSOR, outputValueA);
            IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge{value: outputValueB}(interactionNonce);

        } else {
            // Cheaper to buy
            console2.log('Buying Cheaper');

            // Using univ3 TWAP Oracle to get a lower bound on returned ETH.
            uint256 minAmountOut = getAmountBasedOnTwap(uint128(totalInputValue), WETH, ICETH).mul(auxData).div(1e18);
            IWeth(WETH).deposit{value: totalInputValue}();
            IERC20(WETH).approve(UNIV3_ROUTER, totalInputValue);

            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: WETH,
                tokenOut: ICETH,
                fee: uniFee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: totalInputValue,
                amountOutMinimum: minAmountOut,
                sqrtPriceLimitX96: 0
            });

            outputValueA = ISwapRouter(UNIV3_ROUTER).exactInputSingle(params);
            ISetToken(ICETH).approve(ROLLUP_PROCESSOR, outputValueA);
        }
    }

    /**
    * @dev Function that calculated the output of a swap based on univ3's twap price
    * @dev Based on v3-peripher/contracts/libraries/OracleLibrary.sol modified to 
    * explicilty convert uint32 to int32 to support 0.8.x
    *
    * @param amountIn - Amount to be exchanged
    * @param baseToken - Address of tokens to be exchanged
    * @param quoteToken - Address of tokens to be recevied 
    * @return amountOut - Amount received of quoteToken
    */
    
    function getAmountBasedOnTwap(uint128 amountIn, address baseToken, address quoteToken) 
        internal 
        returns (uint256 amountOut)
    { 
        address pool = IUniswapV3Factory(UNIV3_FACTORY).getPool(
            WETH,
            ICETH,
            3000
        );

        uint32 secondsAgo = 60*10; 

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, ) = IUniswapV3Pool(pool).observe(
            secondsAgos
        );

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 arithmeticmeanTick = int24(tickCumulativesDelta / int32(secondsAgo)); 
        
        if (
            tickCumulativesDelta < 0 && (tickCumulativesDelta % int32(secondsAgo) != 0) 
        ) {
            arithmeticmeanTick--;
        }

        amountOut = getQuoteAtTick(
            arithmeticmeanTick,
            amountIn,
            baseToken,
            quoteToken
        );
    }

    // From v3-peripher/contracts/libraries/OracleLibrary.sol using modified Fullmath and Tickmath for 0.8.x
    function getQuoteAtTick(
        int24 tick, 
        uint128 baseAmount,
        address baseToken,
        address quoteToken
    ) 
        internal 
        pure 
        returns (uint256 quoteAmount) 
    {
        uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(tick);

        // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
        if (sqrtRatioX96 <= type(uint128).max) {
            uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX192, baseAmount, 1 << 192)
                : FullMath.mulDiv(1 << 192, baseAmount, ratioX192);
        } else {
            uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
            quoteAmount = baseToken < quoteToken
                ? FullMath.mulDiv(ratioX128, baseAmount, 1 << 128)
                : FullMath.mulDiv(1 << 128, baseAmount, ratioX128);
        }
    }

    /**
    * @dev Calculates the amount of ETH received from redeeming icETH by taking out a  
    * flashloan of WETH to pay back debt. STETH price based on Lido's Oracle.
    *
    * @param setAmount - Amount of icETH to redeem 
    * @return Expcted amount of ETH returned from redeeming 
    */

    function getEthFromRedeem(uint256 setAmount) internal returns (uint256) {

        (uint256 price, bool safe) = IStethPriceFeed(STETH_PRICE_FEED).current_price(); 
        require(safe, "IndexBridge: Lido oracle price is unsafe");

        IExchangeIssue.LeveragedTokenData memory issueInfo = IExchangeIssue(EXISSUE).getLeveragedTokenData(
            ISetToken(ICETH), 
            setAmount, 
            true
        );        

        IAaveLeverageModule(AAVE_LEVERAGE_MODULE).sync(ISetToken(ICETH));
        uint256 debtOwed = issueInfo.debtAmount.mul(1.0009 ether).div(1e18);
        uint256 colInEth = issueInfo.collateralAmount.mul(price).div(1e18); 

        return colInEth - issueInfo.debtAmount;
    }

    /**
    * @dev Issue icETH with a requirment of a minimum returned tokens 
    * based on Lido's Oracle, cost of flashloan and auxData provided by users. 
    *
    * @param totalInputValue - Total amount of ETH used to issue icETH 
    * @param auxData - Used to specific maximal difference between expected
    * @param issueData - Swapdata specifying path used to convert between 
    * input/debt and collateral when creating a leveraged position through 
    * a flashloan.
    * @return outputValueA - Amount of icETH to return to the Rollupprocessor
    * @return outputValueB - Amount of ETH returned when issuing icETH. A portion of ETH 
    * is always returned when issuing icETH since the issuing function in ExchangeIssuance
    * requires an exact output amount rather than input. 
    */

    function issueIcEth(
        uint256 totalInputValue, 
        uint64 auxData, 
        IExchangeIssue.SwapData memory issueData
        )
        internal 
        returns (uint256 outputValueA, uint256 outputValueB)
    {

        /* Calculate minimum acceptable amount of icETH issued based
        on the value stETH which we get from lido's oracle and the cost of
        taking out a flashloan from aave (0.0009%).
        */

        uint256 costOfOneIc;
        {
            (uint256 price, bool safe) = IStethPriceFeed(STETH_PRICE_FEED).current_price(); 
            require(safe, "IndexBridge: Lido oracle price is unsafe");

            IExchangeIssue.LeveragedTokenData memory data = IExchangeIssue(EXISSUE).getLeveragedTokenData(
                ISetToken(ICETH),
                1e18,
                true
            );

            costOfOneIc = (data.collateralAmount.
                mul(1.0009 ether).
                div(1e18).
                mul(price).
                div(1e18) 
                )
                - data.debtAmount
            ;
        }

        uint256 minAmountOut = totalInputValue.mul(auxData).div(costOfOneIc);

        IExchangeIssue(EXISSUE).issueExactSetFromETH{value: totalInputValue}(
            ISetToken(ICETH),
            minAmountOut,
            issueData,
            issueData
        );

        outputValueA = ISetToken(ICETH).balanceOf(address(this));
        outputValueB = address(this).balance;
    }
}
