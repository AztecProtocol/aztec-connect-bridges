// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;

import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";

// Index-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IndexBridgeContract} from "./../../bridges/indexcoop/IndexBridge.sol";
import {AztecTypes} from "./../../aztec/AztecTypes.sol";
import "../../../lib/forge-std/src/Test.sol";
import { ISetToken } from "./../../bridges/indexcoop/interfaces//ISetToken.sol";

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
        uint256 inputValue = 10 ether;
        uint256 maxPrice = 0.9 ether; // icETH/eth in wad 
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

        ( uint256 outputValueA, uint256 outputValueB, bool isAsync) =
             rollupProcessor.convert(
                address(indexBridge),
                ethAztecAsset,
                empty,
                icethAztecAssetA,
                ethAztecAsset,
                inputValue,
                1,
                maxPrice
        );

        uint256 newicETH = icETH.balanceOf(address(rollupProcessor));
        assertEq(inputValue*maxPrice/1e18, newicETH);

    }


    function testRedeemSet() public{
        uint256 inputValue = 0.9 ether;
        uint256 maxPrice = 0.9 ether; // eth/icETH max price in wad
        deal(address(icETH), address(rollupProcessor), inputValue);

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


        ( uint256 outputValueA, uint256 outputValueB, bool isAsync) =
             rollupProcessor.convert(
                address(indexBridge),
                icethAztecAssetA,
                empty,
                ethAztecAsset,
                empty,
                inputValue,
                1,
                maxPrice
        );

        uint256 newEth = address(rollupProcessor).balance;
        assertGt(newEth, inputValue*maxPrice/1e18);
    }









    /*

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
