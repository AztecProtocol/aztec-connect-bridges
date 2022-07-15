// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;
pragma experimental ABIEncoderV2;
import { DefiBridgeProxy } from "./../../aztec/DefiBridgeProxy.sol";
import { RollupProcessor } from "./../../aztec/RollupProcessor.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IndexBridgeContract } from "./../../bridges/indexcoop/IndexBridge.sol";
import { AztecTypes } from "./../../aztec/AztecTypes.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { TickMath } from "../../bridges/uniswapv3/libraries/TickMath.sol";
import { FullMath } from "../../bridges/uniswapv3/libraries/FullMath.sol";
import {ISwapRouter} from '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import {IQuoter} from '@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol';
import {IUniswapV3Factory} from"@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {ISupplyCapIssuanceHook} from '../../bridges/indexcoop/interfaces/ISupplyCapIssuanceHook.sol';
import {IAaveLeverageModule} from '../../bridges/indexcoop/interfaces/IAaveLeverageModule.sol';
import {ICurvePool} from '../../bridges/indexcoop/interfaces/ICurvePool.sol';
import {IWeth} from '../../bridges/indexcoop/interfaces/IWeth.sol';
import {IExchangeIssue} from '../../bridges/indexcoop/interfaces/IExchangeIssue.sol';
import {ISetToken} from '../../bridges/indexcoop/interfaces/ISetToken.sol';
import {IStableSwapOracle} from '../../bridges/indexcoop/interfaces/IStableSwapOracle.sol';
import {AggregatorV3Interface} from '../../bridges/indexcoop/interfaces/AggregatorV3Interface.sol';

import "../../../lib/forge-std/src/Test.sol";

contract IndexTest is Test {
    using SafeMath for uint256;
    using stdStorage for StdStorage;

    DefiBridgeProxy defiBridgeProxy;
    RollupProcessor rollupProcessor;
    IndexBridgeContract indexBridge;

    address ROLLUP_PROCESSOR;
    address immutable EXISSUE = 0xB7cc88A13586D862B97a677990de14A122b74598;
    address immutable CURVE = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address immutable WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address immutable STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address constant ICETH = 0x7C07F7aBe10CE8e33DC6C5aD68FE033085256A84;
    address immutable STETH_PRICE_FEED = 0xAb55Bf4DfBf469ebfe082b7872557D1F87692Fe6;
    address immutable AAVE_LEVERAGE_MODULE = 0x251Bd1D42Df1f153D86a5BA2305FaADE4D5f51DC;
    address immutable ICETH_SUPPLY_CAP = 0x2622c4BB67992356B3826b5034bB2C7e949ab12B; 
    address immutable STABLE_SWAP_ORACLE = 0x3A6Bd15abf19581e411621D669B6a2bbe741ffD6;

    address immutable UNIV3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address immutable UNIV3_QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address immutable UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984; 
    address immutable CHAINLINK_STETH_ETH = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;

    // Address with a lot of icETH 
    address immutable HOAX_ADDRESS = 0xA400f843f0E577716493a3B0b8bC654C6EE8a8A3;

    AztecTypes.AztecAsset empty;
    AztecTypes.AztecAsset ethAztecAsset = AztecTypes.AztecAsset({
        id: 1,
        erc20Address: ETH ,
        assetType: AztecTypes.AztecAssetType.ETH
    });
    AztecTypes.AztecAsset icethAztecAssetA = AztecTypes.AztecAsset({
        id: 2,
        erc20Address: address(ICETH),
        assetType: AztecTypes.AztecAssetType.ERC20
    });

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

    // ===== Testing that buying/issuing and redeeming/seling returns the expected amount ======
    function testIssueSet(uint256 inputValue) public {
        inputValue = bound(inputValue, 1e18, 500 ether);

        uint64 flowSelector = 1;
        uint64 maxSlipAux = 9800; //maxSlip is has 4 decimals
        uint64 oracleLimit = 9850; // ETH/stETH upper limit  

        uint64 auxData = encodeAuxdataThree(flowSelector, maxSlipAux, oracleLimit);

        (uint256 newICETH, uint256 returnedEth) = issueSet(inputValue, auxData);

        uint256 minAmountOut = getMinIceth((inputValue-returnedEth), maxSlipAux);
        assertGe(newICETH, minAmountOut, 'Less than expected was returned when issuing icETH');
    }

    function testBuySet(uint256 inputValue) public {
        inputValue = bound(inputValue, 1 ether, 500 ether);

        uint64 flowSelector = 5;
        uint64 maxSlipAux = 9900; //maxSlip is has 4 decimals
        uint64 oracleLimit = 9500; // max icETH/ETH price acceptable
        uint64 auxData = encodeAuxdataThree(flowSelector, maxSlipAux, oracleLimit);

        uint24 uniFee = 500;
        bytes memory path = abi.encodePacked(WETH, uniFee);
        path = abi.encodePacked(path, ICETH);

        uint256 icethFromQuoter = IQuoter(UNIV3_QUOTER).quoteExactInput(path, inputValue);
        uint256 minimumReceivedDex = getAmountBasedOnTwap(uint128(inputValue), WETH, ICETH, uniFee).mul(maxSlipAux).div(1e4);

        if (icethFromQuoter < minimumReceivedDex){ // When price impact becomes too large expect a revert.
            bytes4 defaultVar; 
            buySetExpectRevert(inputValue, auxData, bytes('Too little received'), defaultVar);

        } else {
            uint256 newICETH = buySet(inputValue, auxData);
            assertGe(
                newICETH, minimumReceivedDex, 
                "A smaller amount than expected was returned when buying icETH from univ3"
            );
        }
    }

    function testRedeemSet(uint256 inputValue) public{
        inputValue = bound(inputValue, 1e18, 500 ether);

        uint64 maxSlipAux = 9800; //maxSlip is has 4 decimals
        uint64 flowSelector = 1;
        uint64 oracleLimit = 9000; 
        uint64 auxData = encodeAuxdataThree(flowSelector, maxSlipAux, oracleLimit);
        uint256 minimumReceivedRedeem = getMinEth(inputValue, maxSlipAux);

        uint256 receivedBasedOnQuoter = getEthBasedOnQuoter(inputValue); 

        if (receivedBasedOnQuoter < minimumReceivedRedeem) { 
            // If stETH is depegging and the pool is unbalanced
            // swapping from stETH -> ETH can have a large price impact
            // in that case we should revert        

            bytes4 emptyBytes;
            redeemSetExpectRevert(inputValue, auxData, bytes("Exchange resulted in fewer coins than expected"), emptyBytes);

        } else{
            uint256 newEth = redeemSet(inputValue, auxData);
            assertGe(newEth, minimumReceivedRedeem, "Received to little ETH from redeem");
        }
   } 

    function testSellSet(uint256 inputValue) public{
        inputValue = bound(inputValue, 1000, 500 ether);

        uint64 flowSelector = 5;
        uint64 maxSlipAux = 9900; //maxSlip is has 4 decimals
        uint64 oracleLimit = 8000; // min icETH/ETH price. Hisotrically ~0.81-1
        uint64 auxData = encodeAuxdataThree(flowSelector, maxSlipAux, oracleLimit);

        uint24 uniFee = 500;
        bytes memory path = abi.encodePacked(ICETH, uniFee);
        path = abi.encodePacked(path, WETH);
        uint256 ethFromQuoter = IQuoter(UNIV3_QUOTER).quoteExactInput(path, inputValue);
        uint256 minimumReceivedDex = getAmountBasedOnTwap(uint128(inputValue), ICETH, WETH, uniFee).
            mul(maxSlipAux).
            div(1e4)
        ;

        if (ethFromQuoter < minimumReceivedDex){ //If price impact is too large revert when swapping
            bytes4 emptyBytes; 
            sellSetExpectRevert(inputValue, auxData, bytes('Too little received'), emptyBytes);

        } else { //If price impact is not too large swap and receive more or equal to the minimum
            uint256 newEth = sellSet(inputValue, auxData);
            assertGe(newEth, minimumReceivedDex, "Received to little ETH from dex");
        }
   } 

    // ====== Tests that contract reverts if the inputs are incorrect ==========

    function testIncorrectFlowSelector() public {
        uint256 inputValue = 5 ether;
        uint64 flowSelector = 10; // set to an inccorrect number, only 1, 3 or 5 are acceptable
        uint64 maxSlipAux = 9900; //maxSlip is has 4 decimals
        uint64 oracleLimit = 9000; 
        uint64 auxData = encodeAuxdataThree(flowSelector, maxSlipAux, oracleLimit);

        bytes memory emptyBytes;
        buySetExpectRevert(inputValue, auxData, emptyBytes, IndexBridgeContract.IncorrectFlowSelector.selector);
        sellSetExpectRevert(inputValue, auxData, emptyBytes,IndexBridgeContract.IncorrectFlowSelector.selector); 
    }

    function testIncorrectInput() public {
        vm.prank(ROLLUP_PROCESSOR);
        vm.expectRevert(IndexBridgeContract.IncorrectInput.selector);
        indexBridge.convert(
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            AztecTypes.AztecAsset(0, address(0), AztecTypes.AztecAssetType.NOT_USED),
            0,
            0,
            0,
            address(0)
        );
    }

    function testTooSmallInput(uint256 inputValue) public {
        inputValue = bound(inputValue, 1, 1e18);

        uint64 flowSelector = 1;
        uint64 maxSlipAux = 9900; //maxSlip is has 4 decimals
        uint64 oracleLimit = 9000; 
        uint64 auxData = encodeAuxdataThree(flowSelector, maxSlipAux, oracleLimit);

        bytes memory emptyBytes;
        issueSetExpectRevert(inputValue, auxData, emptyBytes, IndexBridgeContract.InputTooSmall.selector);
        redeemSetExpectRevert(inputValue, auxData, emptyBytes, IndexBridgeContract.InputTooSmall.selector);
    }

    /* =========== Testing that contract reverts if Oracle price is unsafe ===============
       oracles are considered unsafe if the price reported is < than the oracleLimit
       entered through the auxData variable. 
    */

    function testUnsafeChainlinkIssueSet(uint256 inputValue) public {
        inputValue = bound(inputValue, 1e18, 500 ether);
        uint64 flowSelector = 1;
        uint64 maxSlipAux = 9900; 

        // Setting Oracle limit low enough to deem oracle price unsafe. 
        uint64 oracleLimit = 9000; 
        uint64 auxData = encodeAuxdataThree(flowSelector, maxSlipAux, oracleLimit);

        bytes memory emptyBytes;
        issueSetExpectRevert(inputValue, auxData, emptyBytes, IndexBridgeContract.UnsafeOraclePrice.selector);
    }

    function testUnsafeTwapBuySet(uint256 inputValue) public {
        inputValue = bound(inputValue, 100, 500 ether);
        uint64 flowSelector = 5;
        uint64 maxSlipAux = 9900; 

        // Setting Oracle upper limit low enough to deem oracle price unsafe. 
        uint64 oracleLimit = 7500; 
        uint64 auxData = encodeAuxdataThree(flowSelector, maxSlipAux, oracleLimit);

        bytes memory emptyBytes;
        buySetExpectRevert(inputValue, auxData, emptyBytes, IndexBridgeContract.UnsafeOraclePrice.selector);
    }

    function testUnsafeChainlinkRedeemSet(uint256 inputValue) public {
        inputValue = bound(inputValue, 1e18, 500 ether);
        uint64 flowSelector = 1;
        uint64 maxSlipAux = 9900; 

        // Setting Oracle lower limit high enough to deem oracle price unsafe. 
        uint64 oracleLimit = 9999; 
        uint64 auxData = encodeAuxdataThree(flowSelector, maxSlipAux, oracleLimit);

        bytes memory emptyBytes;
        redeemSetExpectRevert(inputValue, auxData, emptyBytes, IndexBridgeContract.UnsafeOraclePrice.selector);
    }

    function testUnsafeTwapSellSet(uint256 inputValue) public {
        inputValue = bound(inputValue, 100, 500 ether);
        uint64 flowSelector = 3;
        uint64 maxSlipAux = 9900; 

        // Setting Oracle lower limit high enough to deem oracle price unsafe. 
        uint64 oracleLimit = 9999; 
        uint64 auxData = encodeAuxdataThree(flowSelector, maxSlipAux, oracleLimit);

        bytes memory emptyBytes;
        sellSetExpectRevert(inputValue, auxData, emptyBytes, IndexBridgeContract.UnsafeOraclePrice.selector);
    }


    /* =========== Testing that contract reverts if slippage is to large ===============
        Only tests for issue and redeem will be done here. Testing that contract reverts 
        when buying/sellings is allready done in testBuySet and testSellSet. 
    */

    function testLargeSlipIssueSet(uint256 inputValue) public {
        inputValue = bound(inputValue, 1e18, 500 ether);
        uint64 flowSelector = 1;

        /* Setting maxSlip to >9999 simulating a large slippage.
            minAmount = expectedAmount*maxSlip/1e4, by setting it to >9999
            we force an error due to minAmout being too large, simulating a
            revert cause of slippage.
        */
        uint64 maxSlipAux = 11000; 
        uint64 oracleLimit = 9850; 
        uint64 auxData = encodeAuxdataThree(flowSelector, maxSlipAux, oracleLimit);

        bytes4 emptyBytes;
        issueSetExpectRevert(inputValue, auxData, bytes('ExchangeIssuance: CURVE_OVERSPENT'), emptyBytes);
    }

    function testLargeSlipRedeemSet(uint256 inputValue) public {
        inputValue = bound(inputValue, 1e18, 500 ether);
        uint64 flowSelector = 1;

        /* Setting maxSlip to >9999 simulating a large slippage.
            minAmount = expectedAmount*maxSlip/1e4, by setting it to >9999
            we force an error due to minAmout being too large, simulating a
            revert cause of slippage.
        */
        uint64 maxSlipAux = 11000; 
        uint64 oracleLimit = 9000; 
        uint64 auxData = encodeAuxdataThree(flowSelector, maxSlipAux, oracleLimit);

        bytes4 emptyBytes;
        redeemSetExpectRevert(inputValue, auxData, bytes('Exchange resulted in fewer coins than expected'), emptyBytes);
    }

    // ======== Test that encoding and decode works as expected ======
    function testEncodeDecode() public {
        uint64 flow  = 1;
        uint64 maxSlip  = 9900;
        uint64 oracleLimit  = 9544;
        uint64 encoded = encodeAuxdataThree(flow, maxSlip, oracleLimit);
        (uint64 a, uint64 b, uint64 c) = decodeAuxdataThree(encoded);
        assertEq(flow,a);
        assertEq(maxSlip,b);
        assertEq(oracleLimit,c);
    }

    function encodeAuxdataThree(uint64 a, uint64 b, uint64 c) internal view returns(uint64 encoded) {
        encoded |= (b << 48);
        encoded |= (c << 32);
        encoded |= (a);
        return encoded;
    }

    function decodeAuxdataThree(uint64 encoded) internal view returns (uint64 a, uint64 b, uint64 c) {
        b = encoded >> 48;
        c = (encoded << 16) >> 48;
        a = (encoded << 32) >> 32;
    }

    function getMinEth(uint256 setAmount, uint256 maxSlipAux) internal returns (uint256) {

        ( , int256 intPrice, , , ) = AggregatorV3Interface(CHAINLINK_STETH_ETH).latestRoundData();
        uint256 price = uint256(intPrice);

        IAaveLeverageModule(AAVE_LEVERAGE_MODULE).sync(ISetToken(ICETH));
        IExchangeIssue.LeveragedTokenData memory issueInfo = IExchangeIssue(EXISSUE).getLeveragedTokenData(
            ISetToken(ICETH), 
            setAmount, 
            true
        );        

        uint256 debtOwed = issueInfo.debtAmount.mul(1.0009 ether).div(1e18);
        uint256 colInEth = issueInfo.collateralAmount.mul(price).div(1e18); 

        return (colInEth - debtOwed).mul(maxSlipAux).div(1e4);
    }


    function getEthBasedOnQuoter(uint256 setAmount) internal returns (uint256) {

        IAaveLeverageModule(AAVE_LEVERAGE_MODULE).sync(ISetToken(ICETH));
        IExchangeIssue.LeveragedTokenData memory issueInfo = IExchangeIssue(EXISSUE).getLeveragedTokenData(
            ISetToken(ICETH), 
            setAmount, 
            true
        );        

        uint256 debtOwed = issueInfo.debtAmount.mul(1.0009 ether).div(1e18);
        uint256 colInEth = ICurvePool(CURVE).get_dy(1,0, issueInfo.collateralAmount); 

        return (colInEth - debtOwed);
    }

    function getMinIceth(
        uint256 totalInputValue, 
        uint64 maxSlipAux
        )
        internal 
        returns (uint256 minIcToReceive)
    {
        ( , int256 intPrice, , , ) = AggregatorV3Interface(CHAINLINK_STETH_ETH).latestRoundData();
        uint256 price = uint256(intPrice);

        IAaveLeverageModule(AAVE_LEVERAGE_MODULE).sync(ISetToken(ICETH));
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

        minIcToReceive = totalInputValue.mul(maxSlipAux).mul(1e14).div(costOfOneIc);
    }

    function getAmountBasedOnTwap(
        uint128 amountIn, 
        address baseToken, 
        address quoteToken, 
        uint24 uniFee
        ) 
        internal 
        returns (uint256 amountOut)
    { 
        address pool = IUniswapV3Factory(UNIV3_FACTORY).getPool(
            WETH,
            ICETH,
            uniFee
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

    function issueSet(uint256 inputValue, uint64 auxData) 
        internal 
        returns (uint256 newICETH, uint256 returnedEth)
    {
        deal(address(rollupProcessor), inputValue);

        (newICETH, returnedEth, ) =
             rollupProcessor.convert(
                address(indexBridge),
                ethAztecAsset,
                empty,
                icethAztecAssetA,
                ethAztecAsset,
                inputValue,
                1,
                auxData
        );
    }

    function issueSetExpectRevert(
        uint256 inputValue, 
        uint64 auxData, 
        bytes memory revertMessage, 
        bytes4 revertSelector
    ) 
        internal 
    {
        deal(address(indexBridge), inputValue);

        if (revertSelector == 0){
            vm.expectRevert(revertMessage);
        } else {
            vm.expectRevert(revertSelector);
        } 

        hoax(ROLLUP_PROCESSOR);
        indexBridge.convert(
            ethAztecAsset,
            empty,
            icethAztecAssetA,
            ethAztecAsset,
            inputValue,
            1,
            auxData,
            address(0)
        );
    }

    function buySet(uint256 inputValue, uint64 auxData) 
        internal 
        returns (uint256 newICETH)
    {
        deal(ROLLUP_PROCESSOR, inputValue);
        (newICETH, ,) =
            rollupProcessor.convert(
                address(indexBridge),
                ethAztecAsset,
                empty,
                icethAztecAssetA,
                empty,
                inputValue,
                1,
                auxData
        );
    }

    function buySetExpectRevert(uint256 inputValue, uint64 auxData, bytes memory revertMessage, bytes4 revertSelector) internal {
        deal(address(indexBridge), inputValue);

        if (revertSelector == 0){
            vm.expectRevert(revertMessage);
        } else {
            vm.expectRevert(revertSelector);
        } 

        hoax(ROLLUP_PROCESSOR);
        indexBridge.convert(
            ethAztecAsset,
            empty,
            icethAztecAssetA,
            empty,
            inputValue,
            1,
            auxData,
            address(0)
        );
    }

    function redeemSet(uint256 inputValue, uint64 auxData) internal returns (uint256 newEth) {
        hoax(HOAX_ADDRESS);
        IERC20(ICETH).transfer(address(rollupProcessor), inputValue);

        (newEth, , ) =
             rollupProcessor.convert(
                address(indexBridge),
                icethAztecAssetA,
                empty,
                ethAztecAsset,
                empty,
                inputValue,
                2,
                auxData
        );
    }

    function redeemSetExpectRevert(
        uint256 inputValue, 
        uint64 auxData, 
        bytes memory revertMessage, 
        bytes4 revertSelector
        ) 
        internal 
    {
        hoax(HOAX_ADDRESS);
        IERC20(ICETH).transfer(address(indexBridge), inputValue);

        hoax(ROLLUP_PROCESSOR);

        if (revertSelector == 0){
            vm.expectRevert(revertMessage);
        } else {
            vm.expectRevert(revertSelector);
        } 

        indexBridge.convert(
            icethAztecAssetA,
            empty,
            ethAztecAsset,
            empty,
            inputValue,
            2,
            auxData,
            address(0)
        );
    }

    function sellSet(
        uint256 inputValue, 
        uint64 auxData
        ) 
        internal 
        returns (uint256 newEth) 
    {
        hoax(HOAX_ADDRESS);
        IERC20(ICETH).transfer(address(rollupProcessor), inputValue);

        (newEth, ,) =
            rollupProcessor.convert(
                address(indexBridge),
                icethAztecAssetA,
                empty,
                ethAztecAsset,
                empty,
                inputValue,
                2,
                auxData
        );
    }

    function sellSetExpectRevert(
        uint256 inputValue, 
        uint64 auxData, 
        bytes memory revertMessage,
        bytes4 revertSelector
        ) 
        internal 
    {
        hoax(HOAX_ADDRESS);
        IERC20(ICETH).transfer(address(indexBridge), inputValue);

        hoax(ROLLUP_PROCESSOR);

        if (revertSelector == 0){
            vm.expectRevert(revertMessage);
        } else {
            vm.expectRevert(revertSelector);
        }

        indexBridge.convert(
            icethAztecAssetA,
            empty,
            ethAztecAsset,
            empty,
            inputValue,
            2,
            auxData,
            address(0)
        );
    }
}
