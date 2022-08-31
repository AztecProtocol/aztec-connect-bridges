// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {IDefiBridge} from "../../../aztec/interfaces/IDefiBridge.sol";
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {IWETH} from "../../../interfaces/IWETH.sol";

import {IAccountingToken} from "../../../bridges/abracadabra/interfaces/IAccountingToken.sol";
import {IAbracadabraBridge} from "../../../bridges/abracadabra/interfaces/IAbracadabraBridge.sol";
import {AbracadabraBridge} from "../../../bridges/abracadabra/AbracadabraBridge.sol";

interface IAToken is IERC20, IScaledBalanceToken {
    event Mint(address indexed from, uint256 value, uint256 index);

    function mint(address user, uint256 amount) external returns (bool);

    event Burn(
        address indexed from,
        address indexed target,
        uint256 value
    );

    event BalanceTransfer(
        address indexed from,
        address indexed to,
        uint256 value
    );

    function burn(
        address user,
        address receiverOfUnderlying,
        uint256 amount
    ) external;

    function mintToTreasury(uint256 amount, uint256 index) external;

    function transferOnLiquidation(
        address from,
        address to,
        uint256 value
    ) external;

    function transferUnderlyingTo(address user, uint256 amount)
        external
        returns (uint256);
}

library RoundingMath {
    function mulDiv(
        uint256 _a,
        uint256 _b,
        uint256 _c
    ) internal pure returns (uint256) {
        return (_a * _b) / _c;
    }
}

contract AbracadabraLendingTest is BridgeTestBase {
    using RoundingMath for uint256;
    IERC20 internal constant DAI = IERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    IERC20 internal constant USDT = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 internal constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    IERC20 internal constant WBTC = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599);
    IWETH internal constant WETH = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20[] internal tokens = [DAI, USDT, USDC, WBTC, IERC20(address(WETH))];

    IERC20 internal token;
    IAToken internal aToken;

    IAbracadabraBridge internal abracadabraBridge;
    abracadabraBridge = IAbracadabraBridge(
            new AbracadabraBridge(address(ROLLUP_PROCESSOR))
        );

    function testApprove() public {
        abracadabraBridge.Approve(address(0));
    }

    function testMintUnderlying() public {
        address AToken = abracadabraBridge.underlyingAToken(address(tokens[0]));
        IAccountingToken(AToken).mint(address(this), 1);
    }
}
