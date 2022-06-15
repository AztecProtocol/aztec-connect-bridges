// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;
pragma experimental ABIEncoderV2;
import { DefiBridgeProxy } from "./../../aztec/DefiBridgeProxy.sol";
import { RollupProcessor } from "./../../aztec/RollupProcessor.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IndexBridgeContract } from "./../../bridges/indexcoop/IndexBridge.sol";
import { AztecTypes } from "./../../aztec/AztecTypes.sol";
import "../../../lib/forge-std/src/Test.sol";

import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";

import { TickMath } from "../../bridges/uniswapv3/libraries/TickMath.sol";
import { FullMath } from "../../bridges/uniswapv3/libraries/FullMath.sol";


import {ISwapRouter} from '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import {IQuoter} from '@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol';
import {IUniswapV3Factory} from"@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {IStethPriceFeed} from '../../bridges/indexcoop/interfaces/IStethPriceFeed.sol';
import {ISupplyCapIssuanceHook} from '../../bridges/indexcoop/interfaces/ISupplyCapIssuanceHook.sol';
import {IAaveLeverageModule} from '../../bridges/indexcoop/interfaces/IAaveLeverageModule.sol';
import {ICurvePool} from '../../bridges/indexcoop/interfaces/ICurvePool.sol';
import {IWeth} from '../../bridges/indexcoop/interfaces/IWeth.sol';
import {IExchangeIssue} from '../../bridges/indexcoop/interfaces/IExchangeIssue.sol';
import {ISetToken} from '../../bridges/indexcoop/interfaces/ISetToken.sol';

contract IndexTest is Test {
    using SafeMath for uint256;

    DefiBridgeProxy defiBridgeProxy;
    RollupProcessor rollupProcessor;
    IndexBridgeContract indexBridge;

    address ROLLUP_PROCESSOR;
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


    function _aztecPreSetup() internal {
        defiBridgeProxy = new DefiBridgeProxy();
        rollupProcessor = new RollupProcessor(address(defiBridgeProxy));
    }

    receive() external payable {} 

    function setUp() public {
        _aztecPreSetup();
        indexBridge = new IndexBridgeContract(
            address(rollupProcessor)
        );
        ROLLUP_PROCESSOR = address(rollupProcessor);

    }

    function testIssueSet(uint256 inputValue) public {
        vm.assume(inputValue < 500 ether);
        vm.assume(inputValue > 1e4);
        //uint256 inputValue = 20 ether;

        uint64 flowSelector = 1;
        uint64 maxSlipAux = 9900; //maxSlip is has 4 decimals

        uint64 auxData = encodeAuxdata(flowSelector, maxSlipAux);

        (uint256 newICETH, uint256 returnedEth) = issueSet(inputValue, auxData);
        console2.log('ETH/icETH issuing', 10000*(inputValue-returnedEth)/newICETH);

        uint256 minimumReceivedIssue = getMinIceth(inputValue-returnedEth, maxSlipAux); 

        (uint256 price, bool safe) = IStethPriceFeed(STETH_PRICE_FEED).current_price(); 
        assertTrue(safe, "Swapped on Curve stETH pool with unsafe Lido Oracle");
        assertGe(newICETH, minimumReceivedIssue, "A smaller amount than expected was returned when Issuing icETH");
    }

    function testBuySet(uint256 inputValue) public {
        vm.assume(inputValue < 5 ether);
        vm.assume(inputValue > 1);
        //uint256 inputValue = 5 ether;

        uint64 flowSelector = 3;
        uint64 maxSlipAux = 9900; //maxSlip is has 4 decimals

        uint64 auxData = encodeAuxdata(flowSelector, maxSlipAux);

        //uint128 inputValue = 5 ether;
        uint256 minimumReceivedDex = getAmountBasedOnTwap(uint128(inputValue), WETH, ICETH).mul(maxSlipAux).div(1e4);

        (uint256 newICETH,) = issueSet(inputValue, auxData);
        console2.log('ETH/icETH buying', 10000*(inputValue)/newICETH);

        assertGe(newICETH, minimumReceivedDex, "A smaller amount than expected was returned when buying icETH from univ3");
    }

    function testRedeem(uint256 inputValue) public{
        vm.assume(inputValue < 500 ether);
        vm.assume(inputValue > 1e4);
        //uint256 inputValue = 20 ether;

        uint64 maxSlipAux = 9900; //maxSlip is has 4 decimals
        uint64 flowSelector = 1;

        uint64 auxData = encodeAuxdata(flowSelector, maxSlipAux);

        uint256 minimumReceivedRedeem = getMinEth(inputValue, maxSlipAux);

        address hoaxAddress = 0xA400f843f0E577716493a3B0b8bC654C6EE8a8A3;
        hoax(hoaxAddress, 20);

        IERC20(ICETH).transfer(address(rollupProcessor), inputValue);
        uint256 newEth = redeemSet(inputValue, auxData);  

        console2.log('ETH/icETH when redeeming', 10000*newEth/inputValue);

        (uint256 price, bool safe) = IStethPriceFeed(STETH_PRICE_FEED).current_price(); 
        assertTrue(safe, "Swapped on Curve stETH pool with unsafe Lido Oracle");
        assertGe(newEth, minimumReceivedRedeem, "Received to little ETH from redeem");
   } 

    function testSelling(uint256 inputValue) public{
        vm.assume(inputValue < 5 ether);
        vm.assume(inputValue > 1);
        //uint256 inputValue = 20 ether;
        
        uint64 flowSelector = 3;
        uint64 maxSlipAux = 9900; //maxSlip is has 4 decimals
        uint64 auxData = encodeAuxdata(flowSelector, maxSlipAux);

        uint256 minimumReceivedDex = getAmountBasedOnTwap(uint128(inputValue), ICETH, WETH).mul(maxSlipAux).div(1e4);

        address hoaxAddress = 0xA400f843f0E577716493a3B0b8bC654C6EE8a8A3;
        hoax(hoaxAddress, 20);

        IERC20(ICETH).transfer(address(rollupProcessor), inputValue);
        uint256 newEth = redeemSet(inputValue, auxData);  

        console2.log('ETH/icETH when selling', 10000*newEth/inputValue);

        assertGe(newEth, minimumReceivedDex, "Received to little ETH from dex");

   } 

    function testCannotUseFaultyFlowSelector() public {

        uint256 inputValue = 5 ether;
        uint64 flowSelector = 10;
        uint64 maxSlipAux = 9900; //maxSlip is has 4 decimals
        uint64 auxData = encodeAuxdata(flowSelector, maxSlipAux);

        address hoaxAddress = 0xA400f843f0E577716493a3B0b8bC654C6EE8a8A3;
        hoax(hoaxAddress, 20);
        IERC20(ICETH).transfer(address(rollupProcessor), inputValue);

        vm.expectRevert('Interaction Failed');
        uint256 newEth = redeemSet(inputValue, auxData);  

    }

    function encodeAuxdata(uint64 a, uint64 b) internal view returns(uint64 encoded) {
        encoded |= (b << 32);
        encoded |= (a);
        return encoded;
    }

    function decodeAuxdata(uint64 encoded) internal view returns (uint64 a, uint64 b) {
        b = encoded >> 32;
        a = (encoded << 32) >> 32;
    }

    function redeemSet(uint256 inputValue, uint256 maxPrice) internal returns (uint256) {
        AztecTypes.AztecAsset memory empty;

        AztecTypes.AztecAsset memory ethAztecAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: ETH ,
            assetType: AztecTypes.AztecAssetType.ETH
        });

        AztecTypes.AztecAsset memory icethAztecAssetA = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(ICETH),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        uint256 _maxPrice = maxPrice;
        uint256 _inputValue = inputValue;

        ( uint256 outputValueA, uint256 outputValueB, bool isAsync) =
             rollupProcessor.convert(
                address(indexBridge),
                icethAztecAssetA,
                empty,
                ethAztecAsset,
                empty,
                _inputValue,
                2,
                _maxPrice
        );

        return address(rollupProcessor).balance;

    }


    function issueSet(uint256 inputValue, uint64 auxData) internal returns (uint256, uint256){
        deal(address(rollupProcessor), inputValue);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory ethAztecAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: ETH ,
            assetType: AztecTypes.AztecAssetType.ETH
        });

        AztecTypes.AztecAsset memory icethAztecAssetA = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(ICETH),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        uint256 _inputValue = inputValue;
        uint64 _auxData = auxData;

        ( uint256 outputValueA, uint256 outputValueB, bool isAsync) =
             rollupProcessor.convert(
                address(indexBridge),
                ethAztecAsset,
                empty,
                icethAztecAssetA,
                ethAztecAsset,
                _inputValue,
                1,
                _auxData
        );

        return (outputValueA, outputValueB);
    }

    function getMinEth(uint256 setAmount, uint256 maxSlipAux) internal returns (uint256) {

        (uint256 price, bool safe) = IStethPriceFeed(STETH_PRICE_FEED).current_price(); 

        IExchangeIssue.LeveragedTokenData memory issueInfo = IExchangeIssue(EXISSUE).getLeveragedTokenData(
            ISetToken(ICETH), 
            setAmount, 
            true
        );        

        IAaveLeverageModule(AAVE_LEVERAGE_MODULE).sync(ISetToken(ICETH));
        uint256 debtOwed = issueInfo.debtAmount.mul(1.0009 ether).div(1e18);
        uint256 colInEth = issueInfo.collateralAmount.mul(price).div(1e18); 

        return (colInEth - issueInfo.debtAmount).mul(maxSlipAux).div(1e14);
    }

    function getMinIceth(
        uint256 totalInputValue, 
        uint64 maxSlipAux
        )
        internal 
        returns (uint256 minIcToReceive)
    {
        
        (uint256 price, bool safe) = IStethPriceFeed(STETH_PRICE_FEED).current_price(); 

        IExchangeIssue.LeveragedTokenData memory data = IExchangeIssue(EXISSUE).getLeveragedTokenData(
            ISetToken(ICETH),
            1e18,
            true
        );

        uint256 costOfOneIc = (data.collateralAmount.
            mul(1.0009 ether).
            div(1e18).
            mul(price).
            div(1e18) 
            )
            - data.debtAmount
        ;

        minIcToReceive = totalInputValue.mul(maxSlipAux).mul(1e12).div(costOfOneIc);
    }

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

    function getQuoteAtTick(
            int24 tick, 
            uint128 baseAmount,
            address baseToken,
            address quoteToken
        ) internal pure returns (uint256 quoteAmount) {
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
}
