// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import {BalanceActionWithTrades, DepositActionType, BalanceAction, TradeActionType, MarketParameters, AssetRateParameters} from "./interfaces/NotionalTypes.sol";
import {IDefiBridge} from "../../interfaces/IDefiBridge.sol";
import { AztecTypes }  from "../../aztec/AztecTypes.sol";
import {NotionalProxy} from "./interfaces/notional/NotionalProxy.sol";
import {NotionalViews} from "./interfaces/notional/NotionalViews.sol";
import {CTokenInterface} from "./interfaces/compound/CTokenInterface.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {FCashToken} from "./AztecFCash.sol";
import "@openzeppelin/contracts/utils/Strings.sol";


struct TradeData {
    uint16 currencyId;
    uint8 marketIndex;
    uint40 maturity;
}

interface IRollupProcessor {
    function receiveEthFromBridge(uint256 interactionNonce) external payable;
}

contract NotionalLendingBridge is IDefiBridge {
    address public immutable rollupProcessor;
    NotionalProxy public immutable notionalProxy;
    NotionalViews public immutable notionalView;
    ERC20[] public underlyingTokens;
    CTokenInterface[] public cTokens;
    int256 private constant ASSET_RATE_DECIMAL_DIFFERENCE = 1e10;
    int256 private constant SECOND_IN_YEAR = 360 days;
    mapping(address => mapping(uint => address)) public cashTokenFcashToken;
    mapping(address => address) public fcashTokenCashToken;
    constructor(address _rollupProcessor){
        rollupProcessor = _rollupProcessor;
        notionalProxy = NotionalProxy(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
        notionalView = NotionalViews(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);
    }

    function insertToken(ERC20 underlying, CTokenInterface cToken) external {
        underlyingTokens.push(underlying);
        cTokens.push(cToken);
    }

    function findToken (address token) public view returns (int, bool) {
        int index = -1;
        bool isCtoken = false;
        for (uint i = 0; i < cTokens.length; i++) {
            if (token == address(underlyingTokens[i])) {
                index = int(i);
                break;
            }
            else if(token == address(cTokens[i])){
                index = int(i);
                isCtoken = true;
                break;
            } 
        }
        return (index, isCtoken);
    }

    function canFinalise(uint256) external view returns (bool) {
        return false;
    }

    function convertFromUnderlying(AssetRateParameters memory ar, int256 underlyingBalance)
    internal
    pure
    returns (int256){
    // Calculation here represents:
    // rateDecimals * balance * underlyingPrecision / rate * internalPrecision
    int256 assetBalance = underlyingBalance * ASSET_RATE_DECIMAL_DIFFERENCE * ar.underlyingDecimals / ar.rate;
    return assetBalance;
}
    
    receive() external payable {
    }
    
    function finalise(
        AztecTypes.AztecAsset calldata ,
        AztecTypes.AztecAsset calldata ,
        AztecTypes.AztecAsset calldata ,
        AztecTypes.AztecAsset calldata ,
        uint256,
        uint64
      ) external payable virtual returns (uint256 outputValueA, uint256 outputValueB, bool interactionComplete) {
          return (0, 0, false);
      }
    
    function setUnderlyingToFCashToken(address cToken, uint maturity) public returns(address fcash) {
        require(
            cashTokenFcashToken[cToken][maturity] == address(0),
            "FCASH_TOKEN_SET"
        );
        ERC20 cTokenERC20 = ERC20(cToken);
        fcash = address(new FCashToken(string(abi.encodePacked(cTokenERC20.name(), Strings.toString(maturity))), cTokenERC20.symbol(), 8, maturity));
        cashTokenFcashToken[cToken][maturity] = fcash;
        fcashTokenCashToken[fcash] = cToken;
    }

    function _computeUnderlyingAmt(ERC20 underlyingAddr, CTokenInterface cToken, uint inputAmt,bool isCToken) internal returns(int88 cashAmt) {
        cToken.accrueInterest();
        uint underlyingDecimal = address(underlyingAddr) == address(0) ? 18 : underlyingAddr.decimals();
        if (isCToken) {
            uint exchangeRateCurrent = cToken.exchangeRateCurrent();
            uint mantissa = 10 + underlyingDecimal;
            cashAmt = int88(int(inputAmt * exchangeRateCurrent/(10 ** mantissa)));
        }  else{
            cashAmt = underlyingDecimal > 8 ? int88(int(inputAmt / (10 ** (underlyingDecimal-8)))): int88(int(inputAmt * (10 ** (8 - underlyingDecimal)))) ;
        }
    }


    function decodeAuxData(uint64 auxData) internal pure returns(TradeData memory tradeData) {
        tradeData.currencyId = uint16(auxData >> 48 & 0xFFFF);
        tradeData.marketIndex = uint8(auxData >> 40 & 0xFF);
    }

    function _enter(ERC20 underlyingAddress, CTokenInterface cToken, FCashToken fcash, uint inputAmount, bool isCToken, uint64 auxData) internal returns(uint88) {
        if (isCToken){
            cToken.approve(address(notionalProxy), inputAmount);
        } else {
            if (address(underlyingAddress) != address(0x0)){
                underlyingAddress.approve(address(notionalProxy), inputAmount);
            } else{
                require(msg.value >= inputAmount, "PROVIDE ETH");
            }
        }
        BalanceActionWithTrades memory action;
        action.actionType = isCToken ? DepositActionType.DepositAsset : DepositActionType.DepositUnderlying;
        action.depositActionAmount = inputAmount;
        action.withdrawEntireCashBalance = false;
        action.redeemToUnderlying = false;
        action.withdrawAmountInternalPrecision = 0;
        int88 cashAmt = _computeUnderlyingAmt(underlyingAddress, cToken, inputAmount, isCToken);
        TradeData memory tradeData = decodeAuxData(auxData);
        action.currencyId = tradeData.currencyId;
        int256 fCashAmt = notionalView.getfCashAmountGivenCashAmount( 
            action.currencyId, 
            -cashAmt, 
            uint256(tradeData.marketIndex),
            block.timestamp);
        // accounts for slippage
        fCashAmt = fCashAmt * (100000 - int256(fcash.maturity()-block.timestamp) * 500/ SECOND_IN_YEAR) /100000;
        bytes32 trade = bytes32(uint256(tradeData.marketIndex) << 240 |  uint256(fCashAmt) << 152);
        action.trades = new bytes32[](1);
        action.trades[0] = trade;
        BalanceActionWithTrades[] memory actions = new BalanceActionWithTrades[](1);
        actions[0] = action;
        if (address(underlyingAddress) == address(0x0) && !isCToken ){
            notionalProxy.batchBalanceAndTradeAction{value: inputAmount}(address(this), actions);
        } else{
            notionalProxy.batchBalanceAndTradeAction(address(this), actions);
        }
        fcash.mint(rollupProcessor, uint256(fCashAmt));
        return uint88(uint256(fCashAmt));        
    }

    function _exit(uint index,FCashToken fcash, uint inputValue, bool isCToken, uint64 auxData, uint interactionNonce) internal returns(uint) {
        // first find whether outputAsset is an underlying token or ctoken
        CTokenInterface cToken = cTokens[index];
        ERC20 underlyingAddress = underlyingTokens[index];
        TradeData memory tradeData = decodeAuxData(auxData);
        int cOutputAmount;
        uint prevBalance;
        tradeData.maturity = uint40(fcash.maturity());
        //fcash.transferFrom(msg.sender, address(this), inputValue);
        fcash.burn(inputValue);
        if (isCToken) {
            prevBalance = cToken.balanceOf(address(this));
        } else {
            if (address(underlyingAddress) == address(0)) {
                prevBalance = address(this).balance;
            } else{
                prevBalance = underlyingAddress.balanceOf(address(this));
            }
        }
        if (block.timestamp < tradeData.maturity){
            // under maturity
            (cOutputAmount, ) = notionalView.getCashAmountGivenfCashAmount(tradeData.currencyId, -int88(int256(inputValue)), tradeData.marketIndex,block.timestamp);
            BalanceActionWithTrades memory action;
            action.withdrawAmountInternalPrecision = uint(cOutputAmount);
            action.redeemToUnderlying = !isCToken;
            action.currencyId  = tradeData.currencyId;
            BalanceActionWithTrades[] memory actions = new BalanceActionWithTrades[](1);
            actions[0] = action;
            bytes32 trade = bytes32((1 << 248) | uint256(tradeData.marketIndex) << 240 |  uint256(inputValue) << 152 | 0 << 120);
            action.trades = new bytes32[](1);
            action.trades[0] = trade;
            actions[0] = action;
            notionalProxy.batchBalanceAndTradeAction(address(this), actions);
            //transfer tokens back to rollup processor
        } else {
            AssetRateParameters memory ar = notionalView.getSettlementRate(tradeData.currencyId, tradeData.maturity);
            cOutputAmount = convertFromUnderlying(ar, int256(inputValue));
            BalanceAction memory action;
            action.withdrawAmountInternalPrecision = uint(cOutputAmount);
            action.redeemToUnderlying = !isCToken;
            action.currencyId  = tradeData.currencyId;
            BalanceAction[] memory actions = new BalanceAction[](1);
            actions[0] = action;
            notionalProxy.batchBalanceAction(address(this), actions);
        }
        if (isCToken){
            // reuse the input to save gas
            inputValue = cToken.balanceOf(address(this)) - prevBalance;
            cToken.approve(rollupProcessor, inputValue);
        } else {
            if (address(underlyingAddress) == address(0)) {
                inputValue = address(this).balance - prevBalance;
                IRollupProcessor(rollupProcessor).receiveEthFromBridge{value: inputValue}(interactionNonce);
            }
            else {
                inputValue = underlyingAddress.balanceOf(address(this)) - prevBalance;
                underlyingAddress.approve(rollupProcessor,inputValue);
            }
        }
        return inputValue;
    }


    function convert(AztecTypes.AztecAsset calldata inputAsset,AztecTypes.AztecAsset calldata, AztecTypes.AztecAsset calldata outputAsset,
        AztecTypes.AztecAsset calldata,
        uint256 inputValue,
        uint256 interactionNonce,
        uint64 auxData,
        address
        )
        external
        payable
        returns (
            uint256 outputValue,
            uint256,
            bool isAsync
        )
        {   
            isAsync = false;
            bool isCToken = false;
            int index = -1;
            (index, isCToken) = findToken(inputAsset.erc20Address);
            require(msg.sender == rollupProcessor, "INVALID_CALLER");
            if (index != -1) {
                CTokenInterface cToken = cTokens[uint(index)];
                uint maturity = notionalView.getActiveMarkets(uint16((auxData >> 48)& 0xFFFF))[uint8((auxData >> 40) & 0xFF) - 1].maturity;
                address fCashAddress = cashTokenFcashToken[address(cToken)][maturity];
                if (fCashAddress == address(0)) {
                    fCashAddress = setUnderlyingToFCashToken(address(cToken), maturity);
                }
                outputValue = _enter(underlyingTokens[uint(index)], cToken, FCashToken(fCashAddress),inputValue, isCToken, auxData);
            } else {
                if (fcashTokenCashToken[inputAsset.erc20Address] != address(0)){
                    (index, isCToken) = findToken(outputAsset.erc20Address);
                    outputValue = _exit(uint(index), FCashToken(inputAsset.erc20Address), inputValue, isCToken,auxData,interactionNonce);
                } else {
                    revert("INVALID INPUT");
                }
            }
        }
}