// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;
pragma experimental ABIEncoderV2;
import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";

// Index-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IndexBridgeContract} from "./../../bridges/indexcoop/IndexBridge.sol";
import {AztecTypes} from "./../../aztec/AztecTypes.sol";
import "../../../lib/forge-std/src/Test.sol";
import { ISetToken } from "./../../bridges/indexcoop/interfaces//ISetToken.sol";

import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import '@uniswap/v3-periphery/contracts/libraries/TransferHelper.sol';

import {IQuoter} from '@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol';


interface ICurvePool {
    function coins(uint256) external view returns (address);

    function exchange(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external;

    function exchange_underlying(
        int128 i,
        int128 j,
        uint256 dx,
        uint256 min_dy
    ) external;

    function get_dy_underlying(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);

    function get_dy(
        int128 i,
        int128 j,
        uint256 dx
    ) external view returns (uint256);
}


interface DEXAdapter{

    enum Exchange { None, Quickswap, Sushiswap, UniV3, Curve }

    /* ============ Structs ============ */
    struct Addresses {
        address quickRouter;
        address sushiRouter;
        address uniV3Router;
        address uniV3Quoter;
        address curveAddressProvider;
        address curveCalculator;
        // Wrapped native token (WMATIC on polygon)
        address weth;
    }

    struct SwapData {
        address[] path;
        uint24[] fees;
        address pool;
        Exchange exchange;
    }

    function swapExactTokensForTokens(
        Addresses memory _addresses,
        uint256 _amountIn,
        uint256 _minAmountOut,
        SwapData memory _swapData
    )
        external
        returns (uint256);

    function getAmountOut(
        Addresses memory,
        SwapData memory,
        uint256 
    )
        external
        returns (uint256);
    /*
    function swapExactTokensForTokens(
        address,
        address,
        address,
        address,
        address,
        address,
        address,
        HLuint256,
        uint256,
        address[] memory,
        uint24[] memory,
        address,
        uint8
    )
        external
        returns (uint256);
    */

}

interface ExIssueLike {

    enum Exchange { None, Quickswap, Sushiswap, UniV3, Curve }
    struct SwapData {
        address[] path;
        uint24[] fees;
        address pool;
        Exchange exchange;
    }


    function addresses() external returns(address,address,address,address,address,address,address);

    struct LeveragedTokenData {
        address collateralAToken;
        address collateralToken;
        uint256 collateralAmount;
        address debtToken;
        uint256 debtAmount;
    }

    function getRedeemExactSet(
        ISetToken,
        uint256,
        SwapData memory,
        SwapData memory 
    )
        external
        returns (uint256);

    function getIssueExactSet(
        ISetToken,
        uint256,
        SwapData memory,
        SwapData memory 
    )
        external
        returns (uint256);

    function getLeveragedTokenData(
        ISetToken,
        uint256,
        bool 
    )
        external 
        returns (LeveragedTokenData memory);

    function issueExactSetFromETH(
        ISetToken,
        uint256,
        SwapData memory,
        SwapData memory 
        )   
        external 
        payable
    ;

    function redeemExactSetForETH(
        ISetToken,
        uint256,
        uint256,
        SwapData memory,
        SwapData memory 
        )
        external 
    ;
}

contract IndexTest is Test {
    DefiBridgeProxy defiBridgeProxy;
    RollupProcessor rollupProcessor;
    IndexBridgeContract indexBridge;

    ExIssueLike ExIssue = ExIssueLike(0xB7cc88A13586D862B97a677990de14A122b74598); 
    address curvePoolAddress = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address stethAddress = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address ethAddress = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    ISetToken icETH = ISetToken(0x7C07F7aBe10CE8e33DC6C5aD68FE033085256A84);

    address adapterAddress = 0x25a8803B9B611cc13D807829D73049cd803f6FCa;
    DEXAdapter adapter = DEXAdapter(adapterAddress);

    //ISwapRouter public immutable swapRouter;

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

    }


    function testIssueSet() public {

        uint256 stEthPrice = ICurvePool(curvePoolAddress).get_dy(1, 0, 1 ether);

        ExIssueLike.LeveragedTokenData memory data  = 
            ExIssue.getLeveragedTokenData(icETH, 1 ether, true);

        uint256 icEthValue = (data.collateralAmount*stEthPrice/1e18) - data.debtAmount;

        uint256 inputValue = 10 ether;
        uint256 maxSlip = 0.99 ether; 
        (uint256 newicETH, uint256 refundEth) = issueSet(inputValue, maxSlip);
        console2.log('New icETH', newicETH);
        console2.log('Refunded ETH', refundEth);

        assertLe(maxSlip*(inputValue-refundEth)/icEthValue, newicETH);
        
        console2.log('ETH to icETH ratio', 1000*(inputValue-refundEth)/newicETH);
    }


    function testRedeem() public{
        uint256 stEthPrice = ICurvePool(curvePoolAddress).get_dy(1, 0, 1 ether);

        ExIssueLike.LeveragedTokenData memory data  = 
            ExIssue.getLeveragedTokenData(icETH, 1 ether, true);

        uint256 icEthValue = (data.collateralAmount*stEthPrice/1e18) - data.debtAmount;

        address hoaxAddress = 0xA400f843f0E577716493a3B0b8bC654C6EE8a8A3;
        hoax(hoaxAddress, 10);

        uint256 inputValue = 10 ether;
        uint256 maxSlip = 0.995 ether;
        
        icETH.transfer(address(rollupProcessor), inputValue);
        uint256 newEth = redeemSet(inputValue, maxSlip);  
        
        console2.log('New ETH', newEth);
        console2.log('ETH to icETH ratio', 1000*newEth/inputValue);
        assertLe(inputValue*(icEthValue*maxSlip/1e18)/1e18, newEth);

   } 







    function redeemSet(uint256 inputValue, uint256 maxPrice) internal returns (uint256) {
        AztecTypes.AztecAsset memory empty;

        AztecTypes.AztecAsset memory ethAztecAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: ethAddress ,
            assetType: AztecTypes.AztecAssetType.ETH
        });

        AztecTypes.AztecAsset memory icethAztecAssetA = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(icETH),
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


    function issueSet(uint256 inputValue, uint256 maxPrice) internal returns (uint256, uint256){
        deal(address(rollupProcessor), inputValue);

        AztecTypes.AztecAsset memory empty;
        AztecTypes.AztecAsset memory ethAztecAsset = AztecTypes.AztecAsset({
            id: 1,
            erc20Address: ethAddress ,
            assetType: AztecTypes.AztecAssetType.ETH
        });

        AztecTypes.AztecAsset memory icethAztecAssetA = AztecTypes.AztecAsset({
            id: 2,
            erc20Address: address(icETH),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        uint256 _maxPrice = maxPrice;
        uint256 _inputValue = inputValue;

        ( uint256 outputValueA, uint256 outputValueB, bool isAsync) =
             rollupProcessor.convert(
                address(indexBridge),
                ethAztecAsset,
                empty,
                icethAztecAssetA,
                ethAztecAsset,
                _inputValue,
                1,
                _maxPrice
        );

        return (icETH.balanceOf(address(rollupProcessor)), address(rollupProcessor).balance);
    }







    /*

    function testGetCurvePrice() public{
        uint256 price = ICurvePool(curvePoolAddress).get_dy(1, 0, 1 ether);
        console2.log('Price of stETH/ETH', price);

       ExIssueLike.LeveragedTokenData memory data  = 
            ExIssue.getLeveragedTokenData(icETH, 1 ether, true);


        uint256 icNAV = (data.collateralAmount*price/1e18) - data.debtAmount;

        console2.log('Collateral Amount', data.collateralAmount);
        console2.log('Det Amount', data.debtAmount);

        console2.log('NAV of 1 icETH', icNAV);

    }
    function testPriceCompare() public{
        uint256 inputAmount = 10 ether;

        //deal(wethAddress, address(this), inputAmount);

        //address router = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        address router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;     


        uint24 feee = 3000; 
        address _quoter = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;

        bytes memory path = abi.encodePacked(wethAddress, feee);
        path = abi.encodePacked(path, address(icETH));
        uint256 quote = IQuoter(_quoter).quoteExactInput(path, inputAmount);
        console2.log('Quoted', quote);

        uint24[] memory fee;
        address[] memory pathToSt = new address[](2); 
        pathToSt[0] = ethAddress;
        pathToSt[1] = stethAddress;
        ExIssueLike.SwapData memory  issueData; 

        issueData = ExIssueLike.SwapData(
            pathToSt, 
            fee,
            curvePoolAddress, 
            ExIssueLike.Exchange.Curve
        );


        uint256 cost = ExIssue.getIssueExactSet(icETH, quote, issueData, issueData); 
        console2.log('Issue Sets', cost);
    }

    function testBuySet() public{
        uint256 inputAmount = 1 ether;

        deal(wethAddress, address(this), inputAmount);

        //address router = 0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45;
        address router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;  

        uint24 fee = 3000; 
        address _quoter = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;  
        bytes memory path = abi.encodePacked(wethAddress, fee);
        path = abi.encodePacked(path, address(icETH));
        uint256 quote = IQuoter(_quoter).quoteExactInput(path, inputAmount);
        console2.log('Quoted', quote);

        //approve router  on first token
        IERC20(wethAddress).approve(router, inputAmount);
        // ISwapRouter.ExactInputSingleParams memory params = 

        ISwapRouter.ExactInputSingleParams memory params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn: wethAddress,
                tokenOut: address(icETH),
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: inputAmount,
                amountOutMinimum: 0.000000008 ether,
                sqrtPriceLimitX96: 0
        });

        uint amount = ISwapRouter(router).exactInputSingle(params);
        console.log('Amount out', amount);
    }

    function testTokenData() public {
       ExIssueLike.LeveragedTokenData memory data  = 
            ExIssue.getLeveragedTokenData(icETH, 10000, true);

       console2.log('Collateral Amount', data.collateralAmount); 
       console2.log('Debt Amount', data.debtAmount); 
    }

    function testGetIssueExactSet() public {
       uint256 cost = ExIssue.getIssueExactSet(icETH, 1 ether, issueData, issueData); 
       console2.log('Cost of icETH', cost);
    }

    function testGetRedeemExactSet() public {
        uint256 ethBack = ExIssue.getRedeemExactSet(icETH, 1 ether , redeemData, redeemData);
        console2.log('Eth back from 1 set', ethBack);
    }

    function getRedeemExactSet(uint256 setAmount) internal returns(uint256){
        return ExIssue.getRedeemExactSet(icETH, setAmount , redeemData, redeemData);
    }

    function getIssueExactSet(uint256 setAmount) internal returns(uint256){
        return ExIssue.getIssueExactSet(icETH, setAmount, issueData, issueData); 
    }

    function getTokenData(uint256 setAmount) internal returns(uint256, uint256) {
       ExIssueLike.LeveragedTokenData memory data  = 
            ExIssue.getLeveragedTokenData(icETH, 10000, true);
        
        return (data.collateralAmount, data.debtAmount);

    }

    function redeemSet(uint256 setAmount, uint256 minOutput) internal {
        ExIssue.redeemExactSetForETH(
            icETH,
            setAmount,
            minOutput,
            redeemData,
            redeemData
        );
    }

    function issueSet(uint256 setAmount, uint256 ethInput) internal {
        ExIssue.issueExactSetFromETH{value: ethInput}(
            icETH,
            setAmount,
            issueData,
            issueData 
        );

    }

 */

}
