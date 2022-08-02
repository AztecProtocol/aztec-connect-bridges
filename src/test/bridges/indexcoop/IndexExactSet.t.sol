// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IndexBridgeContract} from "../../../bridges/indexcoop/IndexBridge.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {IAaveLeverageModule} from "../../../interfaces/set/IAaveLeverageModule.sol";
import {IWETH} from "../../../interfaces/IWETH.sol";
import {IExchangeIssuanceLeveraged} from "../../../interfaces/set/IExchangeIssuanceLeveraged.sol";
import {ISetToken} from "../../../interfaces/set/ISetToken.sol";
import {AggregatorV3Interface} from "../../../interfaces/chainlink/AggregatorV3Interface.sol";
import {IQuoter} from "../../../interfaces/uniswapv3/IQuoter.sol";
import {TickMath} from "../../../libraries/uniswapv3/TickMath.sol";
import {FullMath} from "../../../libraries/uniswapv3/FullMath.sol";
import {IUniswapV3Factory} from "../../../interfaces/uniswapv3/IUniswapV3Factory.sol";
import {IUniswapV3PoolDerivedState} from "../../../interfaces/uniswapv3/pool/IUniswapV3PoolDerivedState.sol";
import {ICurvePool} from "../../../interfaces/curve/ICurvePool.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

import {console2} from "forge-std/console2.sol";

contract IndexExactSetTest is BridgeTestBase {
    using SafeERC20 for IERC20;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant ICETH = 0x7C07F7aBe10CE8e33DC6C5aD68FE033085256A84;

    address public constant EXISSUE = 0xB7cc88A13586D862B97a677990de14A122b74598;
    address public constant CURVE = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address public constant STETH_PRICE_FEED = 0xAb55Bf4DfBf469ebfe082b7872557D1F87692Fe6;
    address public constant AAVE_LEVERAGE_MODULE = 0x251Bd1D42Df1f153D86a5BA2305FaADE4D5f51DC;
    address public constant ICETH_SUPPLY_CAP = 0x2622c4BB67992356B3826b5034bB2C7e949ab12B;
    address public constant STABLE_SWAP_ORACLE = 0x3A6Bd15abf19581e411621D669B6a2bbe741ffD6;

    address public constant UNIV3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address public constant UNIV3_QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address public constant UNIV3_FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address public constant CHAINLINK_STETH_ETH = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;

    // Address with a lot of icETH
    address public constant HOAX_ADDRESS = 0xA400f843f0E577716493a3B0b8bC654C6EE8a8A3;

    // The reference to the example bridge
    IndexBridgeContract internal bridge;

    // To store the id of the example bridge after being added
    uint256 private id;

    AztecTypes.AztecAsset public wethAsset;
    AztecTypes.AztecAsset public icethAsset;
    AztecTypes.AztecAsset public ethAsset;
    AztecTypes.AztecAsset public empty;

    IExchangeIssuanceLeveraged.SwapData public issueData;
    IExchangeIssuanceLeveraged.SwapData public issueDataSt;

    event Diff(int256 main);

    receive() external payable {}

    fallback() external payable {}

    function setUp() public {
        uint24[] memory fee;
        address[] memory pathToSt = new address[](2);
        pathToSt[0] = ETH;
        pathToSt[1] = STETH;
        issueData = IExchangeIssuanceLeveraged.SwapData(
            pathToSt,
            fee,
            CURVE,
            IExchangeIssuanceLeveraged.Exchange.Curve
        );

        address[] memory pathToStFromSt = new address[](2);
        pathToStFromSt[0] = STETH;
        pathToStFromSt[1] = STETH;
        issueDataSt = IExchangeIssuanceLeveraged.SwapData(
            pathToStFromSt,
            fee,
            CURVE,
            IExchangeIssuanceLeveraged.Exchange.Curve
        );
    }

    /** Testing if we can calculate an amount of icETH that is as close as possible 
    to requiring inputValue amount of ETH to issue. 

    1) Using oracle price to a first estimate of the amount of icETH.
    2) Using that amount in getIssueExactSet the required amount of ETH.
    3) Adjusting the amount of icETH based on the previous data.
    4) Use getIssueExactSet again on the newly calculate icETH amount.
    5) Check if the above amount is close but less than inputValue.


    getIssueExactSet is not exact since two different swaps on the same curve pools
    are happening when issuing icETH. The getIssueExactSet does not account for that.
    It is therefore possibel to find an amount of icETH that corresponds to an amount of
    ETH that is < inputValue but that would fail a issueExactSetFromETh call due to the above
    error.

    This adds ~ 300-400k gas since getIssueExact is called twice.gg
     */
    function testExactIcETHCalculation() public {
        uint256 inputValue = 100 ether;
        int256 limit = 0.001 ether; //% of inputValue that is acceptable to not use.

        (uint256 exactSet, uint256 calcInputValue) = getExactSet(inputValue, limit);

        console2.log("Final exactSet", exactSet);
        console2.log("Final calcInputValue", calcInputValue);
        console2.log("Unused ETH", inputValue - calcInputValue);

        deal(address(this), inputValue);

        console2.log("inputVata before issue", inputValue);
        console2.log("exactSet before issue", exactSet);
        IExchangeIssuanceLeveraged(EXISSUE).issueExactSetFromETH{value: inputValue}(
            ISetToken(ICETH),
            exactSet,
            issueData,
            issueData
        );

        uint256 currentBalance = IERC20(ICETH).balanceOf(address(this));
        console2.log("Exit Balance", currentBalance);
    }

    function getExactSet(uint256 _inputValue, int256 _limit) public returns (uint256, uint256) {
        int256 limit = (_limit * int256(_inputValue)) / 1e18;
        uint256 exactSet = _getIcethBasedOnOracle(_inputValue);
        console2.log("exactSet from oracle", exactSet); //1077741459418592978
        //exactSet = 1052741459418592978;

        uint256 calcInputValue = IExchangeIssuanceLeveraged(EXISSUE).getIssueExactSet(
            ISetToken(ICETH),
            exactSet,
            issueData,
            issueData
        );

        uint256 price = (calcInputValue * 1e18) / exactSet;
        int256 inputDiff = int256(_inputValue) - int256(calcInputValue);
        emit log_int(inputDiff);
        emit log_int(limit);

        for (uint256 x; x < 2; x++) {
            // loop used to test, will not be used in bridge.

            if (inputDiff > limit) {
                // Need to increse exactSet to account of diff

                console2.log("----Increasing Set-----");
                console2.log("exactSet Before", exactSet);
                exactSet = ((exactSet + (uint256(inputDiff) * 1e18) / price) * 0.9999e18) / 1e18;
                console2.log("exactSet After", exactSet);
                calcInputValue = IExchangeIssuanceLeveraged(EXISSUE).getIssueExactSet(
                    ISetToken(ICETH),
                    exactSet,
                    issueData,
                    issueData
                );

                inputDiff = int256(_inputValue) - int256(calcInputValue);
                emit log_int(inputDiff);
                if (inputDiff < limit && inputDiff > 0) break;
            } else if (inputDiff < 0) {
                // Decrease set tokens

                console2.log("----Decreasing Set-----");
                console2.log("exactSet Before", exactSet);
                exactSet = ((exactSet - (uint256(-inputDiff) * 1e18) / price) * 0.9999e18) / 1e18;

                console2.log("exactSet Before", exactSet);
                calcInputValue = IExchangeIssuanceLeveraged(EXISSUE).getIssueExactSet(
                    ISetToken(ICETH),
                    exactSet,
                    issueData,
                    issueData
                );

                inputDiff = int256(_inputValue) - int256(calcInputValue);
                emit log_int(inputDiff);
                if (inputDiff < limit) break;
            }
        }

        emit log_int(inputDiff);
        if (!(inputDiff < limit && inputDiff > 0)) revert("Could not reach exact set amount");

        return (exactSet, calcInputValue);
    }

    // If we use stETH instead of ETH as the input getIssueExactSet will be exact. We
    // can therefore find a amount of icETH that corresponds to an inputValue that is very
    // the actual inputValue.
    function testExactIcETHFromStETHCalculation() public {
        uint256 inputValue = 300 ether;
        int256 limit = 0.0001 ether; //% of inputValue that is acceptable to leave behind.

        (uint256 exactSet, uint256 calcInputValue) = getExactSetSt(inputValue, limit);

        console2.log("Final exactSet", exactSet);
        console2.log("Final calcInputValue", calcInputValue);
        console2.log("Unused ETH", inputValue - calcInputValue);

        deal(address(this), 10000 ether);
        hoax(0x9EEaC687D95c68a3c147eeaB8d4e7Ce9c7788ffc);
        IERC20(STETH).transfer(address(this), inputValue);

        IERC20(STETH).safeIncreaseAllowance(EXISSUE, type(uint256).max);

        IExchangeIssuanceLeveraged(EXISSUE).issueExactSetFromERC20(
            ISetToken(ICETH),
            exactSet,
            STETH,
            inputValue,
            issueData,
            issueDataSt
        );

        uint256 currentBalance = IERC20(ICETH).balanceOf(address(this));
        console2.log("currentBalance icETH", currentBalance);

        uint256 currentBalanceSt = IERC20(STETH).balanceOf(address(this));
        console2.log("currentBalance stETH", currentBalanceSt);
    }

    function getExactSetSt(uint256 _inputValue, int256 _limit) public returns (uint256, uint256) {
        int256 limit = (_limit * int256(_inputValue)) / 1e18;
        uint256 exactSet = _getIcethBasedOnOracle(_inputValue);
        console2.log("exactSet from oracle", exactSet); // 1077741459418592978
        //exactSet = 1057741459418592978;

        uint256 calcInputValue = IExchangeIssuanceLeveraged(EXISSUE).getIssueExactSet(
            ISetToken(ICETH),
            exactSet,
            issueData,
            issueDataSt
        );

        uint256 price = (calcInputValue * 1e18) / exactSet;
        int256 inputDiff = int256(_inputValue) - int256(calcInputValue);
        emit log_int(inputDiff);
        emit log_int(limit);

        for (uint256 x; x < 2; x++) {
            // loop used to test, will not be used in bridge.

            if (inputDiff > limit) {
                // Need to increse exactSet to account of diff

                console2.log("----Increasing Set-----");
                console2.log("exactSet Before", exactSet);
                exactSet = ((exactSet + (uint256(inputDiff) * 1e18) / price) * 0.9999e18) / 1e18;
                console2.log("exactSet After", exactSet);
                calcInputValue = IExchangeIssuanceLeveraged(EXISSUE).getIssueExactSet(
                    ISetToken(ICETH),
                    exactSet,
                    issueData,
                    issueDataSt
                );

                inputDiff = int256(_inputValue) - int256(calcInputValue);
                emit log_int(inputDiff);
                if (inputDiff < limit && inputDiff > 0) break;
            } else if (inputDiff < 0) {
                // Decrease set tokens

                console2.log("----Decreasing Set-----");
                console2.log("exactSet Before", exactSet);
                exactSet = (exactSet - (uint256(-inputDiff) * 0.999999e18) / price); //0.99999e18/1e18;

                console2.log("exactSet after", exactSet);
                calcInputValue = IExchangeIssuanceLeveraged(EXISSUE).getIssueExactSet(
                    ISetToken(ICETH),
                    exactSet,
                    issueData,
                    issueDataSt
                );
                inputDiff = int256(_inputValue) - int256(calcInputValue);
                emit log_int(inputDiff);
                if (inputDiff < limit) break;
            }
        }
        emit log_int(inputDiff);
        if (!(inputDiff < limit && inputDiff > 0)) revert("Could not reach exact set amount");
        return (exactSet, calcInputValue);
    }

    function _getIcethBasedOnOracle(uint256 _totalInputValue) internal returns (uint256 minIcToReceive) {
        (, int256 intPrice, , , ) = AggregatorV3Interface(CHAINLINK_STETH_ETH).latestRoundData();
        uint256 price = uint256(intPrice);

        IAaveLeverageModule(AAVE_LEVERAGE_MODULE).sync(ISetToken(ICETH));
        IExchangeIssuanceLeveraged.LeveragedTokenData memory data = IExchangeIssuanceLeveraged(EXISSUE)
            .getLeveragedTokenData(ISetToken(ICETH), 1e18, true);

        uint256 costOfOneIc = ((((data.collateralAmount * (1.0009 ether)) / 1e18) * price) / 1e18) - data.debtAmount;

        minIcToReceive = (_totalInputValue * 1e18) / costOfOneIc;
    }
}
