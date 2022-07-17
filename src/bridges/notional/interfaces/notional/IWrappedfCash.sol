// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.4;

import {TokenType} from "./Types.sol";
import {IERC4626} from "./IERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC777} from "@openzeppelin/contracts/token/ERC777/IERC777.sol";

interface IWrappedfCash {
    struct RedeemOpts {
        bool redeemToUnderlying;
        bool transferfCash;
        address receiver;
        // Zero signifies no maximum slippage
        uint32 maxImpliedRate;
    }
    function initialize(uint16 _currencyId, uint40 _maturity) external;

    /// @notice Mints wrapped fCash ERC20 tokens
    function mintViaAsset(
        uint256 _depositAmountExternal,
        uint88 _fCashAmount,
        address _receiver,
        uint32 _minImpliedRate
    ) external;

    function mintViaUnderlying(
        uint256 _depositAmountExternal,
        uint88 _fCashAmount,
        address _receiver,
        uint32 _minImpliedRate
    ) external;

    function redeem(uint256 _amount, RedeemOpts memory _data) external;

    function redeemToAsset(
        uint256 _amount,
        address _receiver,
        uint32 _maxImpliedRate
    ) external;

    function redeemToUnderlying(
        uint256 _amount,
        address _receiver,
        uint32 _maxImpliedRate
    ) external;

    /// @notice Returns the underlying fCash ID of the token
    function getfCashId() external view returns (uint256);

    /// @notice Returns the underlying fCash maturity of the token
    function getMaturity() external view returns (uint40 _maturity);

    /// @notice True if the fCash has matured, assets mature exactly on the block time
    function hasMatured() external view returns (bool);

    /// @notice Returns the underlying fCash currency
    function getCurrencyId() external view returns (uint16 _currencyId);

    /// @notice Returns the components of the fCash idd
    function getDecodedID() external view returns (uint16 _currencyId, uint40 _maturity);

    /// @notice Returns the current market index for this fCash asset. If this returns
    /// zero that means it is idiosyncratic and cannot be traded.
    function getMarketIndex() external view returns (uint8);

    /// @notice Returns the token and precision of the token that this token settles
    /// to. For example, fUSDC will return the USDC token address and 1e6. The zero
    /// address will represent ETH.
    function getUnderlyingToken() external view returns (IERC20 _underlyingToken, int256 _underlyingPrecision);

    /// @notice Returns the asset token which the fCash settles to. This will be an interest
    /// bearing token like a cToken or aToken.
    function getAssetToken()
        external
        view
        returns (
            IERC20 _assetToken,
            int256 _assetPrecision,
            TokenType _tokenType
        );
}

interface IWrappedfCashComplete is IWrappedfCash, IERC777, IERC4626 {}
