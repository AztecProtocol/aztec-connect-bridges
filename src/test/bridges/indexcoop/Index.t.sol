// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IndexBridgeContract} from "../../../bridges/indexcoop/IndexBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {IAaveLeverageModule} from "../../../interfaces/set/IAaveLeverageModule.sol";
import {IWETH} from "../../../interfaces/IWETH.sol";
import {IExchangeIssuanceLeveraged} from "../../../interfaces/set/IExchangeIssuanceLeveraged.sol";
import {ISetToken} from "../../../interfaces/set/ISetToken.sol";
import {AggregatorV3Interface} from "../../../interfaces/chainlink/AggregatorV3Interface.sol";
import {IQuoter} from "../../../interfaces/uniswapv3/IQuoter.sol";
import {TickMath} from "../../../libraries/uniswapv3/TickMath.sol";
import {FullMath} from "../../../libraries/uniswapv3/FullMath.sol";
import {IUniswapV3Factory} from "../../../interfaces/uniswapv3/IUniswapV3Factory.sol";
import {IUniswapV3PoolDerivedState} from "../../../interfaces/uniswapv3/pool/IUniswapV3PoolDerivedState.sol";
import {ICurvePool} from "../../../interfaces/curve/ICurvePool.sol";

import "forge-std/console2.sol"; 

contract IndexTest is BridgeTestBase {
    using SafeMath for uint256;

    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address constant ICETH = 0x7C07F7aBe10CE8e33DC6C5aD68FE033085256A84;
    
    address constant EXISSUE = 0xB7cc88A13586D862B97a677990de14A122b74598;
    address constant CURVE = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address constant STETH_PRICE_FEED = 0xAb55Bf4DfBf469ebfe082b7872557D1F87692Fe6;
    address constant AAVE_LEVERAGE_MODULE = 0x251Bd1D42Df1f153D86a5BA2305FaADE4D5f51DC;
    address constant ICETH_SUPPLY_CAP = 0x2622c4BB67992356B3826b5034bB2C7e949ab12B; 
    address constant STABLE_SWAP_ORACLE = 0x3A6Bd15abf19581e411621D669B6a2bbe741ffD6;

    address constant UNIV3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address constant UNIV3_QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address constant UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984; 
    address constant CHAINLINK_STETH_ETH = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;

    // Address with a lot of icETH 
    address constant HOAX_ADDRESS = 0xA400f843f0E577716493a3B0b8bC654C6EE8a8A3;

    // The reference to the example bridge
    IndexBridgeContract internal bridge;

    // To store the id of the example bridge after being added
    uint256 private id;

    AztecTypes.AztecAsset wethAsset; 
    AztecTypes.AztecAsset icethAsset;
    AztecTypes.AztecAsset ethAsset; 
    AztecTypes.AztecAsset empty; 

    function setUp() public {
        bridge = new IndexBridgeContract(address(ROLLUP_PROCESSOR));
        vm.deal(address(bridge), 0);  

        vm.label(address(bridge), "Index Bridge");

        vm.startPrank(MULTI_SIG);

        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 2000000);
        ROLLUP_PROCESSOR.setSupportedAsset(WETH, 100000);
        ROLLUP_PROCESSOR.setSupportedAsset(ICETH, 100000);

        vm.stopPrank();

        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        wethAsset = getRealAztecAsset(WETH);
        icethAsset = getRealAztecAsset(ICETH);
        ethAsset = getRealAztecAsset(address(0));
    }

    // ===== Testing that buying/issuing and redeeming/seling returns the expected amount ======
    function testIssueSet(uint256 _depositAmount) public {
        _depositAmount = bound(_depositAmount, 1e18, 500 ether);

        uint64 flowSelector = 1; // Selects issue/redeem flow
        uint64 maxSlipAux = 9800; //maxSlip has 4 decimals
        uint64 oracleLimit = 9850; // ETH/stETH upper limit  
        uint64 auxData = _encodeData(flowSelector, maxSlipAux, oracleLimit);

        (uint256 newICETH, uint256 returnedEth) = _issueSet(_depositAmount, auxData);

        uint256 minAmountOut = _getMinIceth((_depositAmount-returnedEth), maxSlipAux);
        assertGe(newICETH, minAmountOut, 'Less than expected was returned when issuing icETH');
    }

    function testBuySet(uint256 _depositAmount) public {
        _depositAmount = bound(_depositAmount, 1e6, 500 ether);

        uint64 flowSelector = 5; // Selects flow to swap with 0.05% pool 
        uint64 maxSlipAux = 9900; 
        uint64 oracleLimit = 9500; // ETH/icETH upper limit
        uint64 auxData = _encodeData(flowSelector, maxSlipAux, oracleLimit);

        uint24 uniFee = 500;
        bytes memory path = abi.encodePacked(WETH, uniFee);
        path = abi.encodePacked(path, ICETH);

        uint256 icethFromQuoter = IQuoter(UNIV3_QUOTER).quoteExactInput(path, _depositAmount);
        uint256 minimumReceivedDex = _getAmountBasedOnTwap(uint128(_depositAmount), WETH, ICETH, uniFee).mul(maxSlipAux).div(1e4);

        if (icethFromQuoter < minimumReceivedDex){ // When price impact becomes too large expect a revert.
            bytes4 defaultVar; 
            _buySetExpectRevert(_depositAmount, auxData, bytes('Too little received'), defaultVar);

        } else {
            uint256 newICETH = _buySet(_depositAmount, auxData);
            assertGe(
                newICETH, minimumReceivedDex, 
                "A smaller amount than expected was returned when buying icETH from univ3"
            );
        }
    }

    function testRedeemSet(uint256 _depositAmount) public{
        _depositAmount = bound(_depositAmount, 1.1e18, 500 ether);

        uint64 maxSlipAux = 9800; 
        uint64 flowSelector = 1;
        uint64 oracleLimit = 9000; // ETH/stETH lower limit.
        uint64 auxData = _encodeData(flowSelector, maxSlipAux, oracleLimit);
        uint256 minimumReceivedRedeem = _getMinEth(_depositAmount, maxSlipAux);

        uint256 receivedBasedOnQuoter = _getEthBasedOnQuoter(_depositAmount); 

        if (receivedBasedOnQuoter < minimumReceivedRedeem) { 
            // If stETH is depegging and the pool is unbalanced
            // swapping from stETH -> ETH can have a large price impact
            // in that case we should revert        

            bytes4 emptyBytes;
            _redeemSetExpectRevert(_depositAmount, auxData, bytes("Exchange resulted in fewer coins than expected"), emptyBytes);

        } else{
            uint256 newEth = _redeemSet(_depositAmount, auxData);
            assertGe(newEth, minimumReceivedRedeem, "Received too little ETH from redeem");
        }
   } 

    function testSellSet(uint256 _depositAmount) public{
        _depositAmount = bound(_depositAmount, 1e6, 500 ether);

        uint64 flowSelector = 5;
        uint64 maxSlipAux = 9900; 
        uint64 oracleLimit = 8000; // ETH/icETH price lower limit. Hisotrically ~0.81-1
        uint64 auxData = _encodeData(flowSelector, maxSlipAux, oracleLimit);

        uint24 uniFee = 500;
        bytes memory path = abi.encodePacked(ICETH, uniFee);
        path = abi.encodePacked(path, WETH);
        uint256 ethFromQuoter = IQuoter(UNIV3_QUOTER).quoteExactInput(path, _depositAmount);

        uint256 minimumReceivedDex = _getAmountBasedOnTwap(uint128(_depositAmount), ICETH, WETH, uniFee).
            mul(maxSlipAux).
            div(1e4)
        ;

        if (ethFromQuoter < minimumReceivedDex){ //If price impact is too large revert when swapping
            bytes4 emptyBytes; 
            _sellSetExpectRevert(_depositAmount, auxData, bytes('Too little received'), emptyBytes);

        } else { 
            uint256 newEth = _sellSet(_depositAmount, auxData);
            assertGe(newEth, minimumReceivedDex, "Received to little ETH from dex");
        }
   } 

    // ====== Tests that contract reverts if the inputs are incorrect ==========
    function testIncorrectFlowSelector() public {
        uint256 _depositAmount = 5 ether;
        uint64 flowSelector = 10; // set to an inccorrect number, only 1, 3 and 5 are correct.
        uint64 maxSlipAux = 9900; 
        uint64 oracleLimit = 9000; 
        uint64 auxData = _encodeData(flowSelector, maxSlipAux, oracleLimit);

        bytes memory emptyBytes;
        _buySetExpectRevert(_depositAmount, auxData, emptyBytes, ErrorLib.InvalidAuxData.selector);
        _sellSetExpectRevert(_depositAmount, auxData, emptyBytes, ErrorLib.InvalidAuxData.selector);

    }

    function testInvalidInput() public {
        vm.prank(address(ROLLUP_PROCESSOR));
        vm.expectRevert(ErrorLib.InvalidInput.selector);
        bridge.convert(
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

    /* 
        Inputs that are too small will result in a loss of precision
        in flashloan calculations. In getAmountBasedOnRedeem() debtOWned
        and colInEth will lose precision. Dito in ExchangeIssuance.
    */
    function testTooSmallInput(uint256 _depositAmount) public {
        _depositAmount = bound(_depositAmount, 1, 1e18);

        uint64 flowSelector = 1;
        uint64 maxSlipAux = 9900; 
        uint64 oracleLimit = 9000; 
        uint64 auxData = _encodeData(flowSelector, maxSlipAux, oracleLimit);

        bytes memory emptyBytes;
        _issueSetExpectRevert(_depositAmount, auxData, emptyBytes, ErrorLib.InvalidInputAmount.selector);
        _redeemSetExpectRevert(_depositAmount, auxData, emptyBytes, ErrorLib.InvalidInputAmount.selector);
    }

    function testInvalidCaller() public {
        vm.expectRevert(ErrorLib.InvalidCaller.selector);
        bridge.convert(emptyAsset, emptyAsset, emptyAsset, emptyAsset, 0, 0, 0, address(0));
    }

    /* =========== Testing that contract reverts if Oracle price is unsafe ===============
       oracles are considered unsafe if the price reported is < than the oracleLimit
       entered through the auxData variable. 
    */

    function testUnsafeChainlinkIssueSet(uint256 _depositAmount) public {
        _depositAmount = bound(_depositAmount, 1e18, 500 ether);
        uint64 flowSelector = 1;
        uint64 maxSlipAux = 9900; 

        // Setting Oracle limit low enough to deem oracle price unsafe. 
        uint64 oracleLimit = 9000; 
        uint64 auxData = _encodeData(flowSelector, maxSlipAux, oracleLimit);

        bytes memory emptyBytes;
        _issueSetExpectRevert(_depositAmount, auxData, emptyBytes, IndexBridgeContract.UnsafeOraclePrice.selector);
    }

    function testUnsafeTwapBuySet(uint256 _depositAmount) public {
        _depositAmount = bound(_depositAmount, 100, 500 ether);
        uint64 flowSelector = 5;
        uint64 maxSlipAux = 9900; 

        // Setting Oracle upper limit low enough to deem oracle price unsafe. 
        uint64 oracleLimit = 7500; 
        uint64 auxData = _encodeData(flowSelector, maxSlipAux, oracleLimit);

        bytes memory emptyBytes;
        _buySetExpectRevert(_depositAmount, auxData, emptyBytes, IndexBridgeContract.UnsafeOraclePrice.selector);
    }

    function testUnsafeChainlinkRedeemSet(uint256 _depositAmount) public {
        _depositAmount = bound(_depositAmount, 1.1e18, 500 ether);
        uint64 flowSelector = 1;
        uint64 maxSlipAux = 9900; 

        // Setting Oracle lower limit high enough to deem oracle price unsafe. 
        uint64 oracleLimit = 9999; 
        uint64 auxData = _encodeData(flowSelector, maxSlipAux, oracleLimit);

        bytes memory emptyBytes;
        _redeemSetExpectRevert(_depositAmount, auxData, emptyBytes, IndexBridgeContract.UnsafeOraclePrice.selector);
    }

    function testUnsafeTwapSellSet(uint256 _depositAmount) public {
        _depositAmount = bound(_depositAmount, 100, 500 ether);
        uint64 flowSelector = 3;
        uint64 maxSlipAux = 9900; 

        // Setting Oracle lower limit high enough to deem oracle price unsafe. 
        uint64 oracleLimit = 9999; 
        uint64 auxData = _encodeData(flowSelector, maxSlipAux, oracleLimit);

        bytes memory emptyBytes;
        _sellSetExpectRevert(_depositAmount, auxData, emptyBytes, IndexBridgeContract.UnsafeOraclePrice.selector);
    }


    /* =========== Testing that contract reverts if slippage is to large ===============
        Only tests for issue and redeem will be done here. Testing that contract reverts 
        when buying/sellings is allready done in testBuySet and testSellSet. 
    */

    function testLargeSlipIssueSet(uint256 _depositAmount) public {
        _depositAmount = bound(_depositAmount, 1.1e18, 500 ether);
        uint64 flowSelector = 1;

        /* Setting maxSlip to >9999 simulating a large slippage.
            minAmount = expectedAmount*maxSlip/1e4, by setting it to >9999
            we force an error due to minAmout being too large, simulating a
            revert cause of slippage.
        */
        uint64 maxSlipAux = 11000; 
        uint64 oracleLimit = 9850; 
        uint64 auxData = _encodeData(flowSelector, maxSlipAux, oracleLimit);

        bytes4 emptyBytes;
        _issueSetExpectRevert(_depositAmount, auxData, bytes('ExchangeIssuance: CURVE_OVERSPENT'), emptyBytes);
    }

    function testLargeSlipRedeemSet(uint256 _depositAmount) public {
        _depositAmount = bound(_depositAmount, 1.1e18, 500 ether);
        uint64 flowSelector = 1;

        /* Setting maxSlip to >9999 simulating a large slippage.
            minAmount = expectedAmount*maxSlip/1e4, by setting it to >9999
            we force an error due to minAmout being too large, simulating a
            revert cause of slippage.
        */
        uint64 maxSlipAux = 11000; 
        uint64 oracleLimit = 9000; 
        uint64 auxData = _encodeData(flowSelector, maxSlipAux, oracleLimit);

        bytes4 emptyBytes;
        _redeemSetExpectRevert(_depositAmount, auxData, bytes('Exchange resulted in fewer coins than expected'), emptyBytes);
    }

    // ======== Test that encoding and decode works as expected ======
    function testEncodeDecode() public {
        uint64 flow  = 1;
        uint64 maxSlip  = 9900;
        uint64 oracleLimit  = 9544;
        uint64 encoded = _encodeData(flow, maxSlip, oracleLimit);
        (uint64 a, uint64 b, uint64 c) = _decodeData(encoded);
        assertEq(flow,a);
        assertEq(maxSlip,b);
        assertEq(oracleLimit,c);
    }

    function _getMinEth(uint256 _setAmount, uint256 _maxSlipAux) internal returns (uint256) {

        ( , int256 intPrice, , , ) = AggregatorV3Interface(CHAINLINK_STETH_ETH).latestRoundData();
        uint256 price = uint256(intPrice);

        IAaveLeverageModule(AAVE_LEVERAGE_MODULE).sync(ISetToken(ICETH));
        IExchangeIssuanceLeveraged.LeveragedTokenData memory issueInfo = 
            IExchangeIssuanceLeveraged(EXISSUE).
            getLeveragedTokenData(
                ISetToken(ICETH), 
                _setAmount, 
                true
        );        

        uint256 debtOwed = issueInfo.debtAmount.mul(1.0009 ether).div(1e18);
        uint256 colInEth = issueInfo.collateralAmount.mul(price).div(1e18); 

        return (colInEth - debtOwed).mul(_maxSlipAux).div(1e4);
    }

    function _getEthBasedOnQuoter(uint256 _setAmount) internal returns (uint256) {
        IAaveLeverageModule(AAVE_LEVERAGE_MODULE).sync(ISetToken(ICETH));
        IExchangeIssuanceLeveraged.LeveragedTokenData memory issueInfo = 
            IExchangeIssuanceLeveraged(EXISSUE).
            getLeveragedTokenData(
            ISetToken(ICETH), 
            _setAmount, 
            true
        );        

        uint256 debtOwed = issueInfo.debtAmount.mul(1.0009 ether).div(1e18);
        uint256 colInEth = ICurvePool(CURVE).get_dy(1,0, issueInfo.collateralAmount); 

        return (colInEth - debtOwed);
    }

    function _getAmountBasedOnTwap(
        uint128 _amountIn, 
        address _baseToken, 
        address _quoteToken, 
        uint24 _uniFee
        ) 
        internal 
        view
        returns (uint256 amountOut)
    { 
        address pool = IUniswapV3Factory(UNIV3_FACTORY).getPool(
            WETH,
            ICETH,
            _uniFee
        );

        uint32 secondsAgo = 10; 

        uint32[] memory secondsAgos = new uint32[](2);
        secondsAgos[0] = secondsAgo;
        secondsAgos[1] = 0;

        (int56[] memory tickCumulatives, ) = IUniswapV3PoolDerivedState(pool).observe(
            secondsAgos
        );

        int56 tickCumulativesDelta = tickCumulatives[1] - tickCumulatives[0];
        int24 arithmeticmeanTick = int24(tickCumulativesDelta / int32(secondsAgo)); 
        
        if (
            tickCumulativesDelta < 0 && (tickCumulativesDelta % int32(secondsAgo) != 0) 
        ) {
            arithmeticmeanTick--;
        }

        amountOut = _getQuoteAtTick(
            arithmeticmeanTick,
            _amountIn,
            _baseToken,
            _quoteToken
        );
    }

    function _getQuoteAtTick(
            int24 _tick, 
            uint128 _baseAmount,
            address _baseToken,
            address _quoteToken
        ) 
        internal pure 
        returns (uint256 quoteAmount) 
    {
            uint160 sqrtRatioX96 = TickMath.getSqrtRatioAtTick(_tick);
            // Calculate quoteAmount with better precision if it doesn't overflow when multiplied by itself
            if (sqrtRatioX96 <= type(uint128).max) {
                uint256 ratioX192 = uint256(sqrtRatioX96) * sqrtRatioX96;
                quoteAmount = _baseToken < _quoteToken
                    ? FullMath.mulDiv(ratioX192, _baseAmount, 1 << 192)
                    : FullMath.mulDiv(1 << 192, _baseAmount, ratioX192);
            } else {
                uint256 ratioX128 = FullMath.mulDiv(sqrtRatioX96, sqrtRatioX96, 1 << 64);
                quoteAmount = _baseToken < _quoteToken
                    ? FullMath.mulDiv(ratioX128, _baseAmount, 1 << 128)
                    : FullMath.mulDiv(1 << 128, _baseAmount, ratioX128);
            }
    }

    function _issueSet(uint256 _depositAmount, uint64 _auxData) 
        internal 
        returns (uint256 newICETH, uint256 returnedEth)
    {

        vm.deal(address(ROLLUP_PROCESSOR), _depositAmount);
        uint256 bridgeId = encodeBridgeId(id, ethAsset, emptyAsset, icethAsset, ethAsset, _auxData);
        sendDefiRollup(bridgeId, _depositAmount);

        newICETH = IERC20(ICETH).balanceOf(address(ROLLUP_PROCESSOR));
        //returnedEth = address(ROLLUP_PROCESSOR).balance - ethBefore;
        returnedEth = address(ROLLUP_PROCESSOR).balance;

    }

    function _issueSetExpectRevert(
        uint256 _depositAmount, 
        uint64 _auxData, 
        bytes memory _revertMessage, 
        bytes4 _revertSelector
    ) 
        internal 
    {
        vm.deal(address(bridge), _depositAmount);

        if (_revertSelector == 0){
            vm.expectRevert(_revertMessage);
        } else {
            vm.expectRevert(_revertSelector);
        } 

        vm.prank(address(ROLLUP_PROCESSOR));
        bridge.convert(
            ethAsset,
            empty,
            icethAsset,
            ethAsset,
            _depositAmount,
            1,
            _auxData,
            address(0)
        );
    }

    function _buySet(uint256 _depositAmount, uint64 _auxData) 
        internal 
        returns (uint256 newICETH)
    {
        vm.deal(address(ROLLUP_PROCESSOR), _depositAmount);

        uint256 bridgeId = encodeBridgeId(id, ethAsset, emptyAsset, icethAsset, emptyAsset, _auxData);
        sendDefiRollup(bridgeId, _depositAmount);
        newICETH = IERC20(ICETH).balanceOf(address(ROLLUP_PROCESSOR));
    }

    function _buySetExpectRevert(
        uint256 _depositAmount, 
        uint64 _auxData, 
        bytes memory _revertMessage, 
        bytes4 _revertSelector) 
        internal 
    {

        vm.deal(address(bridge), _depositAmount);

        if (_revertSelector == 0){
            vm.expectRevert(_revertMessage);
        } else {
            vm.expectRevert(_revertSelector);
        } 

        vm.prank(address(ROLLUP_PROCESSOR));

        bridge.convert(
            ethAsset,
            emptyAsset,
            icethAsset,
            emptyAsset,
            _depositAmount,
            1,
            _auxData,
            address(0)
        );
    }

    function _redeemSet(uint256 _depositAmount, uint64 _auxData) internal returns (uint256 newEth) {
        uint256 ethBefore = address(ROLLUP_PROCESSOR).balance;

        vm.prank(HOAX_ADDRESS);
        IERC20(ICETH).transfer(address(ROLLUP_PROCESSOR), _depositAmount);

        uint256 bridgeId = encodeBridgeId(id, icethAsset, emptyAsset, ethAsset, emptyAsset, _auxData);
        sendDefiRollup(bridgeId, _depositAmount);

        newEth = address(ROLLUP_PROCESSOR).balance - ethBefore;
    }

    function _redeemSetExpectRevert(
        uint256 _depositAmount, 
        uint64 _auxData, 
        bytes memory _revertMessage, 
        bytes4 _revertSelector
        ) 
        internal 
    {
        vm.prank(HOAX_ADDRESS);
        IERC20(ICETH).transfer(address(bridge), _depositAmount);

        vm.prank(address(ROLLUP_PROCESSOR));

        if (_revertSelector == 0){
            vm.expectRevert(_revertMessage);
        } else {
            vm.expectRevert(_revertSelector);
        } 

        bridge.convert(
            icethAsset,
            empty,
            ethAsset,
            empty,
            _depositAmount,
            2,
            _auxData,
            address(0)
        );
    }

    function _sellSet(
        uint256 _depositAmount, 
        uint64 _auxData
        ) 
        internal 
        returns (uint256 newEth) 
    {
        uint256 ethBefore = address(ROLLUP_PROCESSOR).balance;
        vm.prank(HOAX_ADDRESS);

        IERC20(ICETH).transfer(address(ROLLUP_PROCESSOR), _depositAmount);

        uint256 bridgeId = encodeBridgeId(id, icethAsset, emptyAsset, ethAsset, emptyAsset, _auxData);
        sendDefiRollup(bridgeId, _depositAmount);

        newEth = address(ROLLUP_PROCESSOR).balance - ethBefore;
    }

    function _sellSetExpectRevert(
        uint256 _depositAmount, 
        uint64 _auxData, 
        bytes memory _revertMessage,
        bytes4 _revertSelector
        ) 
        internal 
    {
        vm.prank(HOAX_ADDRESS);
        IERC20(ICETH).transfer(address(bridge), _depositAmount);

        vm.prank(address(ROLLUP_PROCESSOR));

        if (_revertSelector == 0){
            vm.expectRevert(_revertMessage);
        } else {
            vm.expectRevert(_revertSelector);
        }

        bridge.convert(
            icethAsset,
            empty,
            ethAsset,
            empty,
            _depositAmount,
            2,
            _auxData,
            address(0)
        );
    }

    function _getMinIceth(
        uint256 _totalInputValue, 
        uint64 _maxSlipAux
        )
        internal 
        returns (uint256 minIcToReceive)
    {
        ( , int256 intPrice, , , ) = AggregatorV3Interface(CHAINLINK_STETH_ETH).latestRoundData();
        uint256 price = uint256(intPrice);

        IAaveLeverageModule(AAVE_LEVERAGE_MODULE).sync(ISetToken(ICETH));
        IExchangeIssuanceLeveraged.LeveragedTokenData memory data = IExchangeIssuanceLeveraged(EXISSUE).getLeveragedTokenData(
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

        minIcToReceive = _totalInputValue.mul(_maxSlipAux).mul(1e14).div(costOfOneIc);
    }

    function _encodeData(uint64 _a, uint64 _b, uint64 _c) internal pure returns (uint64 encoded) {
        encoded |= (_b << 48);
        encoded |= (_c << 32);
        encoded |= (_a);
        return encoded;
    }

    function _decodeData(uint64 _encoded) internal pure returns (uint64 a, uint64 b, uint64 c) {
        b = _encoded >> 48;
        c = (_encoded << 16) >> 48;
        a = (_encoded << 32) >> 32;
    }



}
