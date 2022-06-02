// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { IDefiBridge } from "../../interfaces/IDefiBridge.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AztecTypes } from "../../aztec/AztecTypes.sol";
import { ISetToken } from "./interfaces/ISetToken.sol";


import '@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol';
import {IQuoter} from '@uniswap/v3-periphery/contracts/interfaces/IQuoter.sol';

import "../../../lib/forge-std/src/Test.sol";

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

interface RollupLike {
    function receiveEthFromBridge(uint256) external payable;
}

interface IWETH{
    function balanceOf(address) external view returns (uint);

    function deposit() external payable;

    function withdraw(uint wad) external;

    function transfer(address dst, uint wad) external returns (bool);
}

interface ExIssueLike {

    enum Exchange { None, Quickswap, Sushiswap, UniV3, Curve }
    struct SwapData {
        address[] path;
        uint24[] fees;
        address pool;
        Exchange exchange;
    }

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

contract IndexBridgeContract is IDefiBridge {
    using SafeMath for uint256;

    address immutable rollupProcessor;
    address immutable exIssue = 0xB7cc88A13586D862B97a677990de14A122b74598; 
    address immutable curve = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address immutable weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address immutable steth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address immutable eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address immutable icETH = 0x7C07F7aBe10CE8e33DC6C5aD68FE033085256A84;


    address immutable univ3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;     
    address immutable univ3Quoter = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    uint24 uniFee = 3000; 

    constructor(address _rollupProcessor) public {
        rollupProcessor = _rollupProcessor;
    }

    fallback() external payable{}

    function convert(
        AztecTypes.AztecAsset memory inputAssetA,
        AztecTypes.AztecAsset memory inputAssetB,
        AztecTypes.AztecAsset memory outputAssetA,
        AztecTypes.AztecAsset memory outputAssetB,
        uint256 totalInputValue,
        uint256 interactionNonce,
        uint64 auxData,
        address rollupBeneficiary
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
        require(msg.sender == rollupProcessor, "ExampleBridge: INVALID_CALLER");

        if (inputAssetA.assetType == AztecTypes.AztecAssetType.ETH &&
            outputAssetA.erc20Address == address(icETH) &&
            outputAssetB.assetType == AztecTypes.AztecAssetType.ETH 
        ){

            (outputValueA, outputValueB) = getIcEth(totalInputValue, auxData, interactionNonce); 

        } 
        else if (inputAssetA.erc20Address == address(icETH) &&
            outputAssetA.assetType == AztecTypes.AztecAssetType.ETH  
        ){ 

            outputValueA = getEth(totalInputValue, auxData, interactionNonce);

        }

  }

    function finalise(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata inputAssetB,
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata outputAssetB,
        uint256 interactionNonce,
        uint64 auxData
    ) external payable override returns (uint256, uint256, bool) {
        require(false);
    }


    function getEth(uint256 totalInputValue, uint64 auxData, uint256 interactionNonce) internal 
        returns (uint256 outputValueA) 
    {

        uint256 minAmountOut;

        {
        uint256 price = ICurvePool(curve).get_dy(1, 0, 1 ether);

        ExIssueLike.LeveragedTokenData memory data  = 
            ExIssueLike(exIssue).getLeveragedTokenData(ISetToken(icETH), 1 ether, true);

        uint256 icNAV = (data.collateralAmount*price/1e18) - data.debtAmount;

        minAmountOut = totalInputValue*(auxData*icNAV/1e18)/1e18;

        }

        uint24[] memory fee;
        address[] memory pathToEth = new address[](2); 
        pathToEth[0] = steth;
        pathToEth[1] = eth;

        ExIssueLike.SwapData memory  redeemData; 
        redeemData = ExIssueLike.SwapData(
            pathToEth, 
            fee,
            curve, 
            ExIssueLike.Exchange.Curve
        );

        bytes memory path = abi.encodePacked(address(icETH), uniFee);
        path = abi.encodePacked(path, weth);
        uint256 ethFromDex = IQuoter(univ3Quoter).quoteExactInput(path, totalInputValue);

        uint256 ethFromEx  = ExIssueLike(exIssue).getRedeemExactSet(
            ISetToken(icETH), 
            totalInputValue, 
            redeemData, 
            redeemData
        );

        if (ethFromEx > ethFromDex) {
            console2.log("Redeem Cheaper");
            //Treat auxdata as eth/iceth wad
            uint256 minOutput = auxData*totalInputValue/1e18;
            ISetToken(icETH).approve(address(exIssue), totalInputValue);

            ExIssueLike(exIssue).redeemExactSetForETH(
                ISetToken(icETH),
                totalInputValue,
                minAmountOut,
                redeemData,
                redeemData
            );

            outputValueA = address(this).balance;
            RollupLike(rollupProcessor).receiveEthFromBridge{value: outputValueA}(interactionNonce);
        } else {

            console2.log("Buying Cheaper");
    
            IERC20(icETH).approve(univ3Router, totalInputValue);
            ISwapRouter.ExactInputSingleParams memory params =
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: icETH,
                    tokenOut: weth,
                    fee: uniFee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: totalInputValue,
                    amountOutMinimum: minAmountOut ,               //NOT SAFE !! #ch
                    sqrtPriceLimitX96: 0
            });
            outputValueA = ISwapRouter(univ3Router).exactInputSingle(params);
            uint256 wethBalance = IWETH(weth).balanceOf(address(this));

            IWETH(weth).withdraw(outputValueA);
            RollupLike(rollupProcessor).receiveEthFromBridge{value: outputValueA}(interactionNonce);
        }
        


    }
    
    function getIcEth(uint256 totalInputValue, uint64 auxData, uint256 interactionNonce) 
        internal 
        returns (uint256 outputValueA, uint256 outputValueB) 
    {


        uint256 minAmountOut;

        {
        uint256 price = ICurvePool(curve).get_dy(1, 0, 1 ether);

        ExIssueLike.LeveragedTokenData memory data  = 
            ExIssueLike(exIssue).getLeveragedTokenData(ISetToken(icETH), 1 ether, true);

        uint256 icNAV = (data.collateralAmount*price/1e18) - data.debtAmount; // eth/icETH

        minAmountOut = auxData*totalInputValue/icNAV;

        }

        //Set up Exissue data
        uint24[] memory fee;
        address[] memory pathToSt = new address[](2); 
        pathToSt[0] = eth;
        pathToSt[1] = steth;
        ExIssueLike.SwapData memory issueData = ExIssueLike.SwapData(
            pathToSt, 
            fee,
            curve, 
            ExIssueLike.Exchange.Curve
        );

        //Check if uni is cheaper than Set Issue
        bytes memory path = abi.encodePacked(weth, uniFee);
        path = abi.encodePacked(path, address(icETH));
        uint256 tokensFromDex = IQuoter(univ3Quoter).quoteExactInput(path, totalInputValue);

        uint256 issueCostOfTokens = ExIssueLike(exIssue).getIssueExactSet(
            ISetToken(icETH),
            tokensFromDex, 
            issueData, 
            issueData
        ); 

        // Cheaper to issue
        if (issueCostOfTokens < totalInputValue){
            console2.log("Issuing Cheaper");

            ExIssueLike(exIssue).issueExactSetFromETH{value: totalInputValue}(
                ISetToken(icETH),
                minAmountOut,
                issueData,
                issueData 
            );

            outputValueA = ISetToken(icETH).balanceOf(address(this));
            outputValueB = address(this).balance;
            ISetToken(icETH).approve(rollupProcessor, outputValueA);
            RollupLike(rollupProcessor).receiveEthFromBridge{value: outputValueB}(interactionNonce);

        } else { // Cheaper to buy
            console2.log("Buying Cheaper");
    
            IWETH(weth).deposit{value: totalInputValue}();
            IERC20(weth).approve(univ3Router, totalInputValue);
            ISwapRouter.ExactInputSingleParams memory params =
                ISwapRouter.ExactInputSingleParams({
                    tokenIn: weth,
                    tokenOut: icETH,
                    fee: uniFee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: totalInputValue,
                    amountOutMinimum: minAmountOut ,              
                    sqrtPriceLimitX96: 0
            });

            outputValueA = ISwapRouter(univ3Router).exactInputSingle(params);
            ISetToken(icETH).approve(rollupProcessor, outputValueA);
        }

    }

}
