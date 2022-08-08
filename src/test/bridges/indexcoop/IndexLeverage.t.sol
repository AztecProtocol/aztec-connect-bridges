// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IndexLeverageBridge} from "../../../bridges/indexcoop/IndexLeverageBridge.sol";
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

contract IndexLeverageTest is BridgeTestBase {
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant ICETH = 0x7C07F7aBe10CE8e33DC6C5aD68FE033085256A84;

    address public constant EXISSUE = 0xB7cc88A13586D862B97a677990de14A122b74598;
    address public constant CURVE = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;
    address public constant STETH_PRICE_FEED = 0xAb55Bf4DfBf469ebfe082b7872557D1F87692Fe6;
    address public constant AAVE_LEVERAGE_MODULE = 0x251Bd1D42Df1f153D86a5BA2305FaADE4D5f51DC;
    address public constant ICETH_SUPPLY_CAP = 0x2622c4BB67992356B3826b5034bB2C7e949ab12B;
    address public constant STABLE_SWAP_ORACLE = 0x3A6Bd15abf19581e411621D669B6a2bbe741ffD6;
    address public constant CHAINLINK_STETH_ETH = 0x86392dC19c0b719886221c78AB11eb8Cf5c52812;

    // Address with a lot of icETH
    address public constant HOAX_ADDRESS = 0xA400f843f0E577716493a3B0b8bC654C6EE8a8A3;

    // The reference to the bridge
    IndexLeverageBridge internal bridge;

    // To store the id of the bridge after being added
    uint256 private id;

    AztecTypes.AztecAsset public wethAsset;
    AztecTypes.AztecAsset public icethAsset;
    AztecTypes.AztecAsset public ethAsset;
    AztecTypes.AztecAsset public empty;

    function setUp() public {
        bridge = new IndexLeverageBridge(address(ROLLUP_PROCESSOR));
        vm.deal(address(bridge), 0);

        vm.label(address(bridge), "IndexLeverageBridge");

        vm.startPrank(MULTI_SIG);

        ROLLUP_PROCESSOR.setSupportedBridge(address(bridge), 2000000);
        ROLLUP_PROCESSOR.setSupportedAsset(WETH, 100000);
        ROLLUP_PROCESSOR.setSupportedAsset(ICETH, 100000);

        vm.stopPrank();

        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        wethAsset = getRealAztecAsset(WETH);
        icethAsset = getRealAztecAsset(ICETH);
        ethAsset = getRealAztecAsset(address(0));
    }

    // ===== Testing that buying/issuing and redeeming/selling returns the expected amount ======
    function testIssueSet(uint256 _depositAmount) public {
        _depositAmount = bound(_depositAmount, 1e18, 500 ether);
        uint64 amountOut = 10e17;

        vm.prank(address(ROLLUP_PROCESSOR));
        (uint256 outputValueA, uint256 outputValueB, ) = bridge.convert{value: depositAmount}(
            ethAsset,
            emptyAsset,
            icethAsset,
            ethAsset,
            depositAmount,
            0,
            amountOut,
            address(0)
        );
    }
}
