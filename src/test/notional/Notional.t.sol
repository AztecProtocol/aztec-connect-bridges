// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "../../../lib/ds-test/src/test.sol";
import "../../bridges/notional/AztecNotionalLending.sol";
import {CTokenInterface} from "../../bridges/notional/interfaces/compound/CTokenInterface.sol";
import {IUniswapV2Router02} from "../../bridges/notional/interfaces/IUniswapV2Router02.sol";
import {NotionalViews} from "../../bridges/notional//interfaces/notional/NotionalViews.sol";
import {RollupProcessor} from "./../../aztec/RollupProcessor.sol";
import {DefiBridgeProxy} from "./../../aztec/DefiBridgeProxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

interface Vm {
    function deal(address who, uint256 amount) external;
    function warp(uint x) external;
}

struct Info {
    uint64 currencyId;
    uint64 marketId;
    uint maturity;
    bool underlying;
    uint interactionNonce;
}

contract NotionalTest is DSTest {
    Vm vm = Vm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    address public constant ETH = address(0);
    address public constant CETH = address(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
    address public constant DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address public constant CDAI = address(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public constant CUSDC = address(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
    address public constant WBTC = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    address public constant CWBTC = address(0xC11b1268C1A384e55C48c2391d8d480264A3A7F4);
    IUniswapV2Router02 public constant ROUTER = IUniswapV2Router02(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);
    NotionalViews public constant notional = NotionalViews(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    uint16 public constant ETH_CURRENCYID = 1;
    uint16 public constant DAI_CURRENCYID = 2;
    uint16 public constant USDC_CURRENCYID = 3;
    uint16 public constant WBTC_CURRENCYID = 4;

    AztecTypes.AztecAsset private empty;


    NotionalLendingBridge public bridge;
    RollupProcessor public rollup;
    function setUp() public {
        DefiBridgeProxy proxy = new DefiBridgeProxy();
        rollup = new RollupProcessor(address(proxy));
        bridge =  new NotionalLendingBridge(address(rollup));
        bridge.insertToken(ERC20(ETH),CTokenInterface(CETH));
        bridge.insertToken(ERC20(DAI),CTokenInterface(CDAI));
        bridge.insertToken(ERC20(USDC),CTokenInterface(CUSDC));
        bridge.insertToken(ERC20(WBTC),CTokenInterface(CWBTC));

    }

    receive() external payable {}

    function swap(uint inputAmount, address[] memory path) internal {
        vm.deal(address(this), inputAmount);
        ROUTER.swapExactETHForTokens{value: inputAmount}(0, path, address(rollup), block.timestamp);
    }

    function lend(uint inputAmount, address[] memory path, address lendToken, Info memory info) internal returns(uint balance, uint maturity) {
        AztecTypes.AztecAsset memory inputAsset;
        bool isLendETH = lendToken == address(0);
        if (isLendETH) {
            vm.deal(address(rollup), inputAmount);
        } else {
            swap(inputAmount, path);
        }
        balance = isLendETH ? inputAmount: ERC20(lendToken).balanceOf(address(rollup));
        inputAsset.assetType = isLendETH ? AztecTypes.AztecAssetType.ETH : AztecTypes.AztecAssetType.ERC20;
        inputAsset.erc20Address = lendToken;
        uint64 auxData = (uint64(info.currencyId) << 48) + (info.marketId << 40);
        maturity = notional.getActiveMarkets(uint16(info.currencyId))[info.marketId - 1].maturity;
        if (isLendETH) {
            rollup.convert(address(bridge), inputAsset,empty,empty, empty, balance, info.interactionNonce, auxData);
        } else {
            rollup.convert(address(bridge), inputAsset,empty,empty, empty, balance, info.interactionNonce, auxData);
        }
    }

    function withdraw(uint withdrawAmount, address underlyingAddr ,address ctoken, Info memory info) internal {
        AztecTypes.AztecAsset memory inputAsset;
        AztecTypes.AztecAsset memory outputAsset;
        address fcashToken = bridge.cashTokenFcashToken(ctoken, info.maturity);
        inputAsset.assetType = AztecTypes.AztecAssetType.ERC20;
        inputAsset.erc20Address = fcashToken;
        outputAsset.assetType = AztecTypes.AztecAssetType.ERC20;
        if (info.underlying) {
            outputAsset.erc20Address = underlyingAddr;
            if (underlyingAddr == address(0)) {
                outputAsset.assetType = AztecTypes.AztecAssetType.ETH;
            }
        } else {
            outputAsset.erc20Address = ctoken;
        }
        uint64 auxData = (info.currencyId << 48) + (info.marketId << 40);
        rollup.convert(address(bridge),inputAsset,empty,outputAsset,empty, withdrawAmount, info.interactionNonce, auxData);
    }

    function convertInput(uint x) internal pure returns (uint) {
        x = 1e16 > x ? 1e16 : x;
        x = 1e20 < x ? 1e20 : x;
        return x;
    }

    // test whether when we lend eth, we receive wrapper fcash token back
    function testETHLend(uint x) public{
        x = convertInput(x);
        Info memory info;
        info.currencyId = ETH_CURRENCYID;
        info.marketId = 1;
        info.interactionNonce = 1;
        address[] memory path = new address[](0);
        (, uint maturity) = lend(x, path, ETH, info);
        address fcashToken = bridge.cashTokenFcashToken(CETH, maturity);
        uint balance = FCashToken(fcashToken).balanceOf(address(rollup));
        require(balance > 0, "receive fcash for lending");
    }

    function testETHWithdrawUnderMaturity(uint x) public {
        x = convertInput(x);
        Info memory info;
        info.currencyId = ETH_CURRENCYID;
        info.marketId = 1;
        info.interactionNonce = 1;
        address[] memory path = new address[](0);
        (, uint maturity) = lend(x, path, ETH, info);
        uint prevBalance = address(rollup).balance;
        uint withdrawAmount = ERC20(bridge.cashTokenFcashToken(CETH, maturity)).balanceOf(address(rollup));
        info.maturity = maturity;
        info.underlying = true;
        info.interactionNonce = 2;
        withdraw(withdrawAmount, ETH, CETH , info);
        uint totalRedeemedETH = address(rollup).balance - prevBalance;
        address fcashToken = bridge.cashTokenFcashToken(CETH, maturity);
        require(totalRedeemedETH * 10000 /x > 9900, "should take most of the money back");
        require(FCashToken(fcashToken).balanceOf(address(rollup)) == 0, "fcash should be burned");
    }


    function testETHLendAtAnyTimeWithdraw(uint x, uint time) public {
        time = time > 60 days ? 60 days : time;
        vm.warp(block.timestamp + time);
        x = convertInput(x);
        Info memory info;
        info.currencyId = ETH_CURRENCYID;
        info.marketId = 1;
        info.interactionNonce = 1;
        address[] memory path = new address[](0);
        (,uint maturity) = lend(x, path, ETH, info);
        uint prevBalance = address(rollup).balance;
        uint withdrawAmount = ERC20(bridge.cashTokenFcashToken(CETH, maturity)).balanceOf(address(rollup));
        info.maturity = maturity;
        info.underlying = true;
        info.interactionNonce = 2;
        withdraw(withdrawAmount, ETH, CETH, info);
        uint totalRedeemedETH = address(rollup).balance - prevBalance;
        address fcashToken = bridge.cashTokenFcashToken(CETH, maturity);
        require(totalRedeemedETH * 10000 /x > 9900, "should take most of the money back");
        require(FCashToken(fcashToken).balanceOf(address(rollup)) == 0, "fcash should be burned");
    }


    function testETHLendTwiceAndWithdraw(uint x) public {
        x = convertInput(x);
        // first lend
        address[] memory path = new address[](0);
        Info memory info;
        info.currencyId = ETH_CURRENCYID;
        info.marketId = 1;
        info.interactionNonce = 1;
        (,uint firstMaturity) = lend(x, path, ETH, info);
        address firstFcashToken = bridge.cashTokenFcashToken(CETH, firstMaturity);
        uint firstLendFcashTokenAmt = FCashToken(firstFcashToken).balanceOf(address(rollup));        
        vm.warp(block.timestamp + 30 days);
        // second lend after a month
        info.interactionNonce = 2;
        (, uint secondMaturity) = lend(x, path, ETH, info);
        address secondFcashToken = bridge.cashTokenFcashToken(CETH,secondMaturity);
        uint balance = address(rollup).balance;
        info.maturity = firstMaturity;
        info.underlying = true;
        info.interactionNonce = 3;
        withdraw(firstLendFcashTokenAmt, ETH, CETH, info);
        uint secondLendFCashTokenAmt = FCashToken(secondFcashToken).balanceOf(address(rollup));
        uint firstWithdrawETH = address(rollup).balance - balance;
        info.maturity = secondMaturity;
        info.interactionNonce = 4;
        withdraw(secondLendFCashTokenAmt, ETH, CETH, info);
        uint secondWithdrawETH = address(rollup).balance - firstWithdrawETH - balance;
        require(firstWithdrawETH > x, "should earn interest");
        require(firstWithdrawETH > secondWithdrawETH, "should incur more eth interest");
        require(secondWithdrawETH * 10000 /x  > 9900, "should take most of the money back");
    }

    function testETHLendTwiceDiffMarketsAndWithdraw(uint x) public {
        x = convertInput(x);
        address[] memory path = new address[](0);
        // first lend
        Info memory info;
        info.currencyId = ETH_CURRENCYID;
        info.marketId = 1;
        Info memory info2;
        info2.currencyId = ETH_CURRENCYID;
        info2.marketId = 2;
        info.interactionNonce = 1;
        info2.interactionNonce = 2;
        (,uint firstMaturity) = lend(x, path,ETH, info);
        address firstFcashToken = bridge.cashTokenFcashToken(CETH, firstMaturity);
        uint firstLendFcashTokenAmt = FCashToken(firstFcashToken).balanceOf(address(rollup));
        (,uint secondMaturity) = lend(x, path,ETH, info2);
        address secondFcashToken = bridge.cashTokenFcashToken(CETH,secondMaturity);
        uint balance = address(rollup).balance;
        info.maturity = firstMaturity;
        info.underlying = true;
        info.interactionNonce = 3;
        withdraw(firstLendFcashTokenAmt, ETH, CETH, info);
        uint secondLendFCashTokenAmt = FCashToken(secondFcashToken).balanceOf(address(rollup));
        uint firstWithdrawETH = address(rollup).balance - balance;
        info2.maturity = secondMaturity;
        info2.underlying = true;
        info2.interactionNonce = 4;
        withdraw(secondLendFCashTokenAmt, ETH, CETH, info2);
        uint secondWithdrawETH = address(rollup).balance - firstWithdrawETH - balance;
        require(firstWithdrawETH * 10000/x > 9900, "should take most of the money back");
        require(secondWithdrawETH * 10000 /x  > 9900, "should take most of the money back");
    }


    function testETHWithdrawOverMaturity(uint x) public {
        x = convertInput(x);
        address[] memory path = new address[](0);
        Info memory info;
        info.currencyId = ETH_CURRENCYID;
        info.marketId = 1;
        info.interactionNonce  = 1;
        (,uint maturity) = lend(x, path, ETH, info);
        uint withdrawAmount = ERC20(bridge.cashTokenFcashToken(CETH, maturity)).balanceOf(address(rollup));
        uint prevBalance = address(rollup).balance;
        vm.warp(block.timestamp + 90 days);
        info.maturity = maturity;
        info.underlying = true;
        info.interactionNonce = 2;
        withdraw(withdrawAmount, ETH, CETH, info);
        uint totalRedeemedETH = address(rollup).balance - prevBalance;
        address fcashToken = bridge.cashTokenFcashToken(CETH, maturity);
        require(totalRedeemedETH > x, "should incur interest");
        require(FCashToken(fcashToken).balanceOf(address(rollup)) == 0, "fcash should be burned");
    }

    function testETHPartialWithdrawUnderMaturity(uint x) public {
        x = convertInput(x);
        Info memory info;
        info.currencyId = ETH_CURRENCYID;
        info.marketId = 1;
        address[] memory path = new address[](0);
        info.interactionNonce = 1;
        (,uint maturity) = lend(x, path, ETH, info);
        uint prevBalance = address(rollup).balance;
        uint withdrawAmount = ERC20(bridge.cashTokenFcashToken(CETH, maturity)).balanceOf(address(rollup));
        info.maturity = maturity;
        info.underlying = true;
        info.interactionNonce = 2;
        withdraw(withdrawAmount/2, ETH, CETH, info);
        uint totalRedeemedETH = address(rollup).balance - prevBalance;
        address fcashToken = bridge.cashTokenFcashToken(CETH, maturity);
        require(totalRedeemedETH * 10000 / (x/2) > 9900, "should take roughly 1/2 of the money back");
        require(totalRedeemedETH * 10000 / x < 5000, "should not take all of the money back");
        require(FCashToken(fcashToken).balanceOf(address(rollup)) == withdrawAmount - withdrawAmount/2, "half of the fcash should remain");
    }

    function testETHPartialWithdrawOverMaturity(uint x) public {
        x = convertInput(x);
        Info memory info;
        info.currencyId = ETH_CURRENCYID;
        info.marketId = 1;
        info.interactionNonce = 1;
        address[] memory path = new address[](0);
        (,uint maturity) = lend(x, path, ETH, info);
        uint withdrawAmount = ERC20(bridge.cashTokenFcashToken(CETH, maturity)).balanceOf(address(rollup));
        uint prevBalance = address(rollup).balance;
        vm.warp(block.timestamp + 90 days);
        info.maturity = maturity;
        info.underlying = true;
        info.interactionNonce = 2;
        withdraw(withdrawAmount/2, ETH, CETH, info);
        uint totalRedeemedETH = address(rollup).balance - prevBalance;
        address fcashToken = bridge.cashTokenFcashToken(CETH, maturity);
        require(totalRedeemedETH > x/2, "should incur interest on the half of the withdraw amount");
        require(totalRedeemedETH * 10000 / x < 6000, "should not take all of the money back");
        require(FCashToken(fcashToken).balanceOf(address(rollup)) == withdrawAmount - withdrawAmount/2, "half of the fcash should remain");
    }

    function testETHWithdrawOverMaturityWithdrawCETH(uint x) public {
        x = convertInput(x);
        Info memory info;
        info.currencyId = ETH_CURRENCYID;
        info.marketId = 1;
        address[] memory path = new address[](0);
        info.interactionNonce = 1;
        (,uint maturity) = lend(x, path, ETH, info);
        uint withdrawAmount = ERC20(bridge.cashTokenFcashToken(CETH, maturity)).balanceOf(address(rollup));
        vm.warp(block.timestamp + 90 days);
        info.maturity = maturity;
        info.underlying = false;
        info.interactionNonce = 2;
        withdraw(withdrawAmount,ETH, CETH, info);
        address fcashToken = bridge.cashTokenFcashToken(CETH, maturity);
        require(CTokenInterface(CETH).balanceOf(address(rollup)) > 0, "should receive CETH");
        require(FCashToken(fcashToken).balanceOf(address(rollup)) == 0, "fcash should be burned");
    }

    function testCDAILend(uint x) public{
        x = convertInput(x);
        address[] memory path = new address[](3);
        path[0] = WETH;
        path[1] = DAI;
        path[2] = CDAI;
        Info memory info;
        info.currencyId = DAI_CURRENCYID;
        info.marketId = 1;
        info.interactionNonce = 1;
        (,uint maturity) = lend(x, path, CDAI, info);
        address fcashToken = bridge.cashTokenFcashToken(CDAI, maturity);
        uint balance = FCashToken(fcashToken).balanceOf(address(rollup));
        require(balance > 0, "receive fcash for lending");
    }

    function testCDAIWithdrawUnderMaturity(uint x) public {
        x = convertInput(x);
        address[] memory path = new address[](3);
        path[0] = WETH;
        path[1] = DAI;
        path[2] = CDAI;
        Info memory info;
        info.currencyId = DAI_CURRENCYID;
        info.marketId = 1;
        info.interactionNonce = 1;
        ( uint inputAmount, uint maturity) = lend(x, path, CDAI, info);
        uint prevBalance = CTokenInterface(CDAI).balanceOf(address(rollup));
        uint withdrawAmount = ERC20(bridge.cashTokenFcashToken(CDAI, maturity)).balanceOf(address(rollup));
        info.maturity = maturity;
        info.underlying = false;
        info.interactionNonce = 2;
        withdraw(withdrawAmount, DAI, CDAI, info);
        uint redeemedBalance = CTokenInterface(CDAI).balanceOf(address(rollup)) - prevBalance;
        require(redeemedBalance * 10000 / inputAmount > 9900, "should take most of money back");
        require(ERC20(bridge.cashTokenFcashToken(CDAI, maturity)).balanceOf(address(rollup)) == 0,"fcash should be burned");
    }

    function testCDAIWithdrawOverMaturity(uint x) public {
        x = convertInput(x);
        address[] memory path = new address[](3);
        path[0] = WETH;
        path[1] = DAI;
        path[2] = CDAI;
        Info memory info;
        info.currencyId = DAI_CURRENCYID;
        info.marketId = 1;
        info.interactionNonce = 1;
        ( uint inputAmount, uint maturity) = lend(x, path, CDAI, info);
        uint prevBalance = CTokenInterface(CDAI).balanceOf(address(rollup));
        uint withdrawAmount = ERC20(bridge.cashTokenFcashToken(CDAI, maturity)).balanceOf(address(rollup));
        vm.warp(block.timestamp + 90 days);
        info.maturity = maturity;
        info.underlying = false;
        info.interactionNonce = 2;
        withdraw(withdrawAmount, DAI, CDAI, info);
        uint redeemedBalance = CTokenInterface(CDAI).balanceOf(address(rollup)) - prevBalance;
        require(redeemedBalance  > inputAmount, "should incur interest");
        require(ERC20(bridge.cashTokenFcashToken(CDAI, maturity)).balanceOf(address(rollup)) == 0,"fcash should be burned");
    }


    function testUSDCLend(uint x) public{
        x = convertInput(x);
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;
        Info memory info;
        info.currencyId = USDC_CURRENCYID;
        info.marketId = 1;
        info.interactionNonce = 1;
        ( , uint maturity) = lend(x, path, USDC,info);
        address fcashToken = bridge.cashTokenFcashToken(CUSDC, maturity);
        uint balance = FCashToken(fcashToken).balanceOf(address(rollup));
        require(balance > 0, "receive fcash for lending");
    }

    function testUSDCWithdrawUnderMaturity(uint x) public {
        x = convertInput(x);
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;
        Info memory info;
        info.currencyId = USDC_CURRENCYID;
        info.marketId = 1;
        info.interactionNonce = 1;
        (uint inputAmount, uint maturity) = lend(x, path, USDC,info);
        uint prevBalance = ERC20(USDC).balanceOf(address(rollup));
        uint withdrawAmount = ERC20(bridge.cashTokenFcashToken(CUSDC, maturity)).balanceOf(address(rollup));
        info.maturity = maturity;
        info.underlying = true;
        info.interactionNonce = 2;
        withdraw(withdrawAmount, USDC, CUSDC, info);
        uint redeemedBalance = ERC20(USDC).balanceOf(address(rollup)) - prevBalance;
        require(redeemedBalance * 10000 / inputAmount > 9900, "should take most of money back");
        require(ERC20(bridge.cashTokenFcashToken(CUSDC, maturity)).balanceOf(address(rollup)) == 0,"fcash should be burned");
    }

    function testUSDCWithdrawOverMaturity(uint x) public {
        x = convertInput(x);
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = USDC;
        Info memory info;
        info.currencyId = USDC_CURRENCYID;
        info.marketId = 1;
        info.interactionNonce = 1;
        (uint inputAmount, uint maturity) = lend(x, path, USDC, info);
        uint prevBalance = ERC20(USDC).balanceOf(address(rollup));
        uint withdrawAmount = ERC20(bridge.cashTokenFcashToken(CUSDC, maturity)).balanceOf(address(rollup));
        vm.warp(block.timestamp + 90 days);
        info.maturity = maturity;
        info.underlying = true;
        info.interactionNonce = 2;
        withdraw(withdrawAmount, USDC, CUSDC, info);
        uint redeemedBalance = ERC20(USDC).balanceOf(address(rollup)) - prevBalance;
        require(redeemedBalance  > inputAmount, "should incur interest");
        require(ERC20(bridge.cashTokenFcashToken(CUSDC, maturity)).balanceOf(address(rollup)) == 0,"fcash should be burned");
    }


    function testWBTCLend(uint x) public{
        x = convertInput(x);
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = WBTC;
        Info memory info;
        info.currencyId = WBTC_CURRENCYID;
        info.marketId = 1;
        info.interactionNonce = 1;
        ( , uint maturity) = lend(x, path, WBTC,info);
        address fcashToken = bridge.cashTokenFcashToken(CWBTC, maturity);
        uint balance = FCashToken(fcashToken).balanceOf(address(rollup));
        require(balance > 0, "receive fcash for lending");
    }

    function testWBTCWithdrawUnderMaturity(uint x) public {
        x = convertInput(x);
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = WBTC;
        Info memory info;
        info.currencyId = WBTC_CURRENCYID;
        info.marketId = 1;
        info.interactionNonce = 1;
        (uint inputAmount, uint maturity) = lend(x, path, WBTC,info);
        uint prevBalance = ERC20(WBTC).balanceOf(address(rollup));
        uint withdrawAmount = ERC20(bridge.cashTokenFcashToken(CWBTC, maturity)).balanceOf(address(rollup));
        info.maturity = maturity;
        info.underlying = true;
        info.interactionNonce = 2;
        withdraw(withdrawAmount, WBTC, CWBTC, info);
        uint redeemedBalance = ERC20(WBTC).balanceOf(address(rollup)) - prevBalance;
        require(redeemedBalance * 10000 / inputAmount > 9900, "should take most of money back");
        require(ERC20(bridge.cashTokenFcashToken(CWBTC, maturity)).balanceOf(address(rollup)) == 0,"fcash should be burned");
    }

    function testWBTCWithdrawOverMaturity(uint x) public {
        x = convertInput(x);
        address[] memory path = new address[](2);
        path[0] = WETH;
        path[1] = WBTC;
        Info memory info;
        info.currencyId = WBTC_CURRENCYID;
        info.marketId = 1;
        info.interactionNonce = 1;
        (uint inputAmount, uint maturity) = lend(x, path, WBTC,info);
        uint prevBalance = ERC20(WBTC).balanceOf(address(rollup));
        uint withdrawAmount = ERC20(bridge.cashTokenFcashToken(CWBTC, maturity)).balanceOf(address(rollup));
        vm.warp(block.timestamp + 90 days);
        info.maturity = maturity;
        info.underlying = true;
        info.interactionNonce = 2;
        withdraw(withdrawAmount, WBTC, CWBTC, info);
        uint redeemedBalance = ERC20(WBTC).balanceOf(address(rollup)) - prevBalance;
        require(redeemedBalance * 10000 / inputAmount > 9900, "should take most of money back");
        require(ERC20(bridge.cashTokenFcashToken(CWBTC, maturity)).balanceOf(address(rollup)) == 0,"fcash should be burned");
    }
}
