// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.4;

struct MarketParameters {
    bytes32 storageSlot;
    uint256 maturity;
    // Total amount of fCash available for purchase in the market.
    int256 totalfCash;
    // Total amount of cash available for purchase in the market.
    int256 totalAssetCash;
    // Total amount of liquidity tokens (representing a claim on liquidity) in the market.
    int256 totalLiquidity;
    // This is the previous annualized interest rate in RATE_PRECISION that the market traded
    // at. This is used to calculate the rate anchor to smooth interest rates over time.
    uint256 lastImpliedRate;
    // Time lagged version of lastImpliedRate, used to value fCash assets at market rates while
    // remaining resistent to flash loan attacks.
    uint256 oracleRate;
    // This is the timestamp of the previous trade
    uint256 previousTradeTime;
}

enum TokenType {
    UnderlyingToken,
    cToken,
    cETH,
    Ether,
    NonMintable,
    aToken
}

struct Token {
    address tokenAddress;
    bool hasTransferFee;
    int256 decimals;
    TokenType tokenType;
    uint256 maxCollateralBalance;
}

interface NotionalViews {
    function getCurrencyId(address _tokenAddress) external view returns (uint16 currencyId);

    function getActiveMarkets(uint16 _currencyId) external view returns (MarketParameters[] memory);

    function getfCashAmountGivenCashAmount(
        uint16 _currencyId,
        int88 _netCashToAccount,
        uint256 _marketIndex,
        uint256 _blockTime
    ) external view returns (int256);

    function getCashAmountGivenfCashAmount(
        uint16 _currencyId,
        int88 _fCashAmount,
        uint256 _marketIndex,
        uint256 _blockTime
    ) external view returns (int256, int256);

    function getMaxCurrencyId() external view returns (uint16);

    function getCurrency(uint16 _currencyId)
        external
        view
        returns (Token memory assetToken, Token memory underlyingToken);
}
