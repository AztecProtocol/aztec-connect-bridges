pragma solidity >=0.8.4;

import {ISetToken} from "./ISetToken.sol";

interface IExchangeIssuanceLeveraged {
    enum Exchange {
        None,
        Quickswap,
        Sushiswap,
        UniV3,
        Curve
    }
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
    ) external returns (uint256);

    function getIssueExactSet(
        ISetToken,
        uint256,
        SwapData memory,
        SwapData memory
    ) external returns (uint256);

    function getLeveragedTokenData(
        ISetToken,
        uint256,
        bool
    ) external returns (LeveragedTokenData memory);

    function issueExactSetFromETH(
        ISetToken,
        uint256,
        SwapData memory,
        SwapData memory
    ) external payable;

    function issueExactSetFromERC20(
        ISetToken,
        uint256,
        address,
        uint256,
        SwapData memory,
        SwapData memory
    ) external;

    function redeemExactSetForETH(
        ISetToken,
        uint256,
        uint256,
        SwapData memory,
        SwapData memory
    ) external;
}
