// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma experimental ABIEncoderV2;

import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { IDefiBridge } from "../../interfaces/IDefiBridge.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { AztecTypes } from "../../aztec/AztecTypes.sol";
import { ISetToken } from "./interfaces/ISetToken.sol";


interface RollupLike {
    function receiveEthFromBridge(uint256) external payable;
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

    if (inputAssetA.assetType == AztecTypes.AztecAssetType.ETH){

        {

        uint24[] memory fee;
        address[] memory pathToSt = new address[](2); 
        pathToSt[0] = eth;
        pathToSt[1] = steth;
        ExIssueLike.SwapData memory  issueData; 

        issueData = ExIssueLike.SwapData(
            pathToSt, 
            fee,
            curve, 
            ExIssueLike.Exchange.Curve
        );

        // Treating auxData as max price for icETH/eth in wad 
        uint256 setAmount = totalInputValue*auxData/1e18;
        ExIssueLike(exIssue).issueExactSetFromETH{value: totalInputValue}(
            ISetToken(icETH),
            setAmount,
            issueData,
            issueData 
        );

        outputValueA = ISetToken(icETH).balanceOf(address(this));
        outputValueB = address(this).balance;
        ISetToken(icETH).approve(rollupProcessor, outputValueA);
        RollupLike(rollupProcessor).receiveEthFromBridge{value: outputValueB}(interactionNonce);

        }

    } else if (inputAssetA.erc20Address == address(icETH)){ 

       { 
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

        //Treat auxdata as eth/iceth wad

        uint256 minOutput = auxData*totalInputValue/1e18;
        ISetToken(icETH).approve(address(exIssue), totalInputValue);

        ExIssueLike(exIssue).redeemExactSetForETH(
            ISetToken(icETH),
            totalInputValue,
            minOutput,
            redeemData,
            redeemData
        );

        outputValueA = address(this).balance;
        RollupLike(rollupProcessor).receiveEthFromBridge{value: outputValueA}(interactionNonce);
       }

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
}
