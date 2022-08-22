// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {NotionalBridgeContract} from "../../../bridges/notional/NotionalBridge.sol";
import {IWrappedfCashFactory} from "../../../interfaces/notional/IWrappedfCashFactory.sol";
import {NotionalViews} from "../../../interfaces/notional/INotionalViews.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
struct Info {
    uint16 currencyId;
    uint40 maturity;
    bool underlying;
    uint256 interactionNonce;
}

contract NotionalTest is BridgeTestBase {
    address public constant ETH = address(0);
    address public constant CETH = address(0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5);
    address public constant DAI = address(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    address public constant CDAI = address(0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643);
    address public constant WETH = address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant USDC = address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address public constant CUSDC = address(0x39AA39c021dfbaE8faC545936693aC917d5E7563);
    address public constant WBTC = address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    address public constant CWBTC = address(0xccF4429DB6322D5C611ee964527D42E5d685DD6a);
    mapping(address => uint16) public currencyId;
    address[8] public tokens;
    uint256[8] public lowerBound;
    uint256[8] public upperBound;
    mapping(address => address) public underlyingTokenToAssetToken;
    mapping(address => address) public assetTokenToUnderlyingToken;
    mapping(address => bool) public underlyingToken;
    IWrappedfCashFactory public constant FCASH_FACTORY =
        IWrappedfCashFactory(0x5D051DeB5db151C2172dCdCCD42e6A2953E27261);
    AztecTypes.AztecAsset private empty;
    NotionalBridgeContract public bridge;
    NotionalViews public notionalView = NotionalViews(0x1344A36A1B56144C3Bc62E7757377D288fDE0369);

    function setUp() public {
        bridge = new NotionalBridgeContract(address(ROLLUP_PROCESSOR));
        // Approve ERC20 tokens for ROLLUP_PROCESSOR
        tokens[0] = ETH;
        tokens[1] = CETH;
        tokens[2] = DAI;
        tokens[3] = CDAI;
        tokens[4] = USDC;
        tokens[5] = CUSDC;
        tokens[6] = WBTC;
        tokens[7] = CWBTC;
        currencyId[ETH] = 1;
        currencyId[CETH] = 1;
        currencyId[DAI] = 2;
        currencyId[CDAI] = 2;
        currencyId[USDC] = 3;
        currencyId[CUSDC] = 3;
        currencyId[WBTC] = 4;
        currencyId[CWBTC] = 4;
        lowerBound[0] = 1e16;
        lowerBound[1] = 1e8;
        lowerBound[2] = 1e16;
        lowerBound[3] = 1e9;
        lowerBound[4] = 1e6;
        lowerBound[5] = 1e9;
        lowerBound[6] = 1e5;
        lowerBound[7] = 1e6;
        upperBound[0] = 1e20;
        upperBound[1] = 1e12;
        upperBound[2] = 1e22;
        upperBound[3] = 1e15;
        upperBound[4] = 1e12;
        upperBound[5] = 1e15;
        upperBound[6] = 1e9;
        upperBound[7] = 1e10;
        underlyingTokenToAssetToken[ETH] = CETH;
        underlyingTokenToAssetToken[WETH] = CETH;
        underlyingTokenToAssetToken[DAI] = CDAI;
        underlyingTokenToAssetToken[WBTC] = CWBTC;
        underlyingTokenToAssetToken[USDC] = CUSDC;
        assetTokenToUnderlyingToken[CETH] = ETH;
        assetTokenToUnderlyingToken[CUSDC] = USDC;
        assetTokenToUnderlyingToken[CWBTC] = WBTC;
        assetTokenToUnderlyingToken[CDAI] = DAI;
        underlyingToken[ETH] = true;
        underlyingToken[WETH] = true;
        underlyingToken[DAI] = true;
        underlyingToken[USDC] = true;
        underlyingToken[WBTC] = true;
        bridge.preApproveForAll();
        vm.label(address(bridge), "Notional Bridge");
    }

    function testLendAndWithdraw(
        uint256 _x,
        uint8 _tokenIndex,
        bool _withdrawUnderlying
    ) public {
        _tokenIndex = uint8(bound(uint256(_tokenIndex), 0, tokens.length - 1));
        _x = bound(_x, lowerBound[_tokenIndex], upperBound[_tokenIndex]);
        address token = tokens[_tokenIndex];
        Info memory info;
        info.currencyId = currencyId[token];
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        info.interactionNonce = 1;
        address fcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        _lend(_x, token, info);
        uint256 fcashBalance = ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        if (fcashBalance == 0) {
            revert("receive fcash for lending");
        }
        info.underlying = _withdrawUnderlying;
        info.interactionNonce = 2;
        // check balance
        address withdrawnToken;
        if (_withdrawUnderlying) {
            if (underlyingToken[token]) {
                withdrawnToken = token;
            } else {
                withdrawnToken = assetTokenToUnderlyingToken[token];
            }
        } else {
            if (underlyingToken[token]) {
                withdrawnToken = underlyingTokenToAssetToken[token];
            } else {
                withdrawnToken = token;
            }
        }
        uint256 withdrawnAmount = _withdraw(fcashBalance, withdrawnToken, info);
        if (token != withdrawnToken) {
            // convert amount to underlying amount
            if (info.underlying) {
                _x = bridge.computeUnderlyingAmount(token, withdrawnToken, _x);
                uint256 decimals = withdrawnToken == ETH ? 18 : ERC20(withdrawnToken).decimals();
                if (decimals >= 8) {
                    _x = _x * 10**(decimals - 8);
                } else {
                    _x = _x / (10**(8 - decimals));
                }
            } else {
                withdrawnAmount = bridge.computeUnderlyingAmount(withdrawnToken, token, withdrawnAmount);
                uint256 decimals = token == ETH ? 18 : ERC20(token).decimals();
                if (decimals >= 8) {
                    withdrawnAmount = withdrawnAmount * 10**(decimals - 8);
                } else {
                    withdrawnAmount = withdrawnAmount / (10**(8 - decimals));
                }
            }
        }
        if ((withdrawnAmount * 10000) / _x < 9900) {
            revert("should take most of money back");
        }
    }

    function testETHLendTwiceAndWithdraw(uint256 _x) public {
        _x = bound(_x, lowerBound[0], upperBound[0]);
        // first lend
        Info memory info;
        info.currencyId = currencyId[ETH];
        info.interactionNonce = 1;
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        uint40 firstMaturity = info.maturity;
        address firstFcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        _lend(_x, ETH, info);
        uint256 firstLendFcashTokenAmt = ERC20(firstFcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        vm.warp(block.timestamp + 15 days);
        // second lend after 15 days
        info.interactionNonce = 2;
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        uint40 secondMaturity = info.maturity;
        address secondFcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        _lend(_x, ETH, info);
        uint256 balance = address(ROLLUP_PROCESSOR).balance;
        info.maturity = firstMaturity;
        info.underlying = true;
        info.interactionNonce = 3;
        _withdraw(firstLendFcashTokenAmt, ETH, info);
        uint256 secondLendFCashTokenAmt = ERC20(secondFcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 firstWithdrawETH = address(ROLLUP_PROCESSOR).balance - balance;
        info.maturity = secondMaturity;
        info.interactionNonce = 4;
        _withdraw(secondLendFCashTokenAmt, ETH, info);
        uint256 secondWithdrawETH = address(ROLLUP_PROCESSOR).balance - firstWithdrawETH - balance;
        if (firstWithdrawETH < secondWithdrawETH) {
            revert("should incur more eth interest");
        }
        if ((secondWithdrawETH * 10000) / _x < 9900) {
            revert("should take most of money back");
        }
    }

    function testETHPartialWithdraw(uint256 _x, bool _overMaturity) public {
        _x = bound(_x, lowerBound[0], upperBound[0]);
        Info memory info;
        info.currencyId = currencyId[ETH];
        info.interactionNonce = 1;
        info.maturity = uint40(notionalView.getActiveMarkets(info.currencyId)[0].maturity);
        address fcashToken = FCASH_FACTORY.deployWrapper(info.currencyId, info.maturity);
        _lend(_x, ETH, info);
        uint256 withdrawnAmount = ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR));
        uint256 prevBalance = address(ROLLUP_PROCESSOR).balance;
        if (_overMaturity) {
            vm.warp(block.timestamp + 90 days);
        }
        info.underlying = true;
        info.interactionNonce = 2;
        _withdraw(withdrawnAmount / 2, ETH, info);
        uint256 redeemedBalance = address(ROLLUP_PROCESSOR).balance - prevBalance;
        if ((redeemedBalance * 10000) / (_x / 2) < 9900) {
            revert("should take most of money back");
        }
        if (ERC20(fcashToken).balanceOf(address(ROLLUP_PROCESSOR)) < withdrawnAmount / 2) {
            revert("should still have fcash");
        }
    }

    function _lend(
        uint256 _inputAmount,
        address _lendToken,
        Info memory _info
    ) internal {
        AztecTypes.AztecAsset memory inputAsset;
        AztecTypes.AztecAsset memory outputAsset;
        bool isLendETH = _lendToken == address(0);
        if (isLendETH) {
            vm.deal(address(ROLLUP_PROCESSOR), _inputAmount + 1 ether);
        } else {
            deal(_lendToken, address(bridge), _inputAmount);
            vm.deal(address(ROLLUP_PROCESSOR), 1 ether);
        }
        uint256 balance = isLendETH ? _inputAmount : ERC20(_lendToken).balanceOf(address(bridge));
        inputAsset.assetType = isLendETH ? AztecTypes.AztecAssetType.ETH : AztecTypes.AztecAssetType.ERC20;
        inputAsset.erc20Address = _lendToken;
        outputAsset.assetType = AztecTypes.AztecAssetType.ERC20;
        outputAsset.erc20Address = FCASH_FACTORY.computeAddress(_info.currencyId, _info.maturity);
        vm.label(outputAsset.erc20Address, "fcash token");
        vm.prank(address(ROLLUP_PROCESSOR));
        uint256 fcashAmount;
        if (isLendETH) {
            (fcashAmount, , ) = bridge.convert{value: _inputAmount}(
                inputAsset,
                empty,
                outputAsset,
                empty,
                balance,
                _info.interactionNonce,
                uint64(1),
                address(0)
            );
        } else {
            (fcashAmount, , ) = bridge.convert(
                inputAsset,
                empty,
                outputAsset,
                empty,
                balance,
                _info.interactionNonce,
                uint64(1),
                address(0)
            );
        }
        vm.prank(address(ROLLUP_PROCESSOR));
        ERC20(outputAsset.erc20Address).transferFrom(address(bridge), address(ROLLUP_PROCESSOR), fcashAmount);
    }

    function _withdraw(
        uint256 _withdrawnAmount,
        address _token,
        Info memory _info
    ) internal returns (uint256) {
        AztecTypes.AztecAsset memory inputAsset;
        AztecTypes.AztecAsset memory outputAsset;
        address fcashToken = FCASH_FACTORY.computeAddress(_info.currencyId, _info.maturity);
        inputAsset.assetType = AztecTypes.AztecAssetType.ERC20;
        inputAsset.erc20Address = fcashToken;
        outputAsset.assetType = AztecTypes.AztecAssetType.ERC20;
        uint64 auxData = 0;
        if (_info.underlying) {
            if (underlyingToken[_token]) {
                outputAsset.erc20Address = _token;
                outputAsset.assetType = AztecTypes.AztecAssetType.ERC20;
            } else {
                outputAsset.erc20Address = assetTokenToUnderlyingToken[_token];
                outputAsset.assetType = AztecTypes.AztecAssetType.ERC20;
            }
        } else {
            if (underlyingToken[_token]) {
                outputAsset.erc20Address = underlyingTokenToAssetToken[_token];
                outputAsset.assetType = AztecTypes.AztecAssetType.ERC20;
            } else {
                outputAsset.erc20Address = _token;
                outputAsset.assetType = AztecTypes.AztecAssetType.ERC20;
            }
        }
        if (outputAsset.erc20Address == ETH) {
            outputAsset.assetType = AztecTypes.AztecAssetType.ETH;
        }

        vm.prank(address(ROLLUP_PROCESSOR));
        ERC20(fcashToken).transfer(address(bridge), _withdrawnAmount);
        vm.prank(address(ROLLUP_PROCESSOR));
        (uint256 outputAmount, , ) = bridge.convert(
            inputAsset,
            empty,
            outputAsset,
            empty,
            _withdrawnAmount,
            _info.interactionNonce,
            auxData,
            address(0)
        );
        if (outputAsset.assetType == AztecTypes.AztecAssetType.ERC20) {
            vm.prank(address(ROLLUP_PROCESSOR));
            ERC20(outputAsset.erc20Address).transferFrom(address(bridge), address(ROLLUP_PROCESSOR), outputAmount);
        }
        return outputAmount;
    }
}
