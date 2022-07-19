// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.10;
pragma experimental ABIEncoderV2;
import {BridgeTestBase} from "./../../aztec/base/BridgeTestBase.sol";
import {ErrorLib} from "../../../bridges/base/ErrorLib.sol";

import {console} from "../../../../lib/forge-std/src/console.sol";
import {Vm} from "../../../../lib/forge-std/src/Vm.sol";

// Example-specific imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {INonfungiblePositionManager} from "../../../interfaces/uniswapv3/INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "../../../interfaces/uniswapv3/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "../../../interfaces/uniswapv3/IUniswapV3Pool.sol";
import {TickMath} from "../../../libraries/uniswapv3/TickMath.sol";
import {UniLPBridge} from "../../../bridges/uniswapv3/UniLPBridge.sol";
import {TransferHelper, ISwapRouter} from "../../../bridges/uniswapv3/ParentUniLPBridge.sol";
import {AztecTypes} from "../../../aztec/libraries/AztecTypes.sol";
import {LiquidityAmounts} from "../../../libraries/uniswapv3/LiquidityAmounts.sol";

contract UniswapTest is BridgeTestBase {
    IERC20 private constant DAI = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7);
    IERC20 private constant WETH = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    IERC20 private constant USDC = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    address private constant FACTORY = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address private constant ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address private constant NONFUNGIBLE_POSITION_MANAGER = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;
    address private constant QUOTER = 0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6;
    address private constant POOL = 0x4e68Ccd3E89f51C3074ca5072bbAC773960dFa36;
    address[] private tokens = [address(DAI), address(WETH), address(USDC)];
    UniLPBridge private syncBridge;

    uint256 private id;

    function setUp() public {
        vm.label(FACTORY, "FACTORY");
        vm.label(ROUTER, "ROUTER");
        vm.label(NONFUNGIBLE_POSITION_MANAGER, "MANAGER");
        vm.label(address(DAI), "DAI");
        vm.label(address(WETH), "WETH");
        vm.label(address(USDC), "USDC");

        syncBridge = new UniLPBridge(address(ROLLUP_PROCESSOR));

        vm.label(address(syncBridge), "SYNCBRIDGE");
        vm.prank(MULTI_SIG);
        ROLLUP_PROCESSOR.setSupportedBridge(address(syncBridge), 200000);
        id = ROLLUP_PROCESSOR.getSupportedBridgesLength();

        for (uint256 i = 0; i < tokens.length; i++) {
            if (!isSupportedAsset(tokens[i])) {
                vm.prank(MULTI_SIG);
                ROLLUP_PROCESSOR.setSupportedAsset(tokens[i], 100000);
            }
        }

        vm.deal(address(syncBridge), uint256(10000));
        vm.deal(address(this), uint256(10000));
    }

    function testTwoPartMint(uint256 _deposit, uint256 _ethDeposit) public {
        //revert();
        _deposit = bound(_deposit, 1000000000000, 11090954464882723182754300279390208);
        _ethDeposit = bound(_ethDeposit, 100000000000000, 218809284046322613163859525526366);

        //this is the point at which maxLiquidityPerTick is triggered. fair to say at this point the test is passing and this is
        //the logical upper boundary for the test range, as these numbers are something like 218 trillion eth and
        //several hundred trillion DAI, or something else extremely large

        //_setTokenBalance(address(DAI), address(syncBridge), _deposit, 2);
        deal(address(DAI), address(syncBridge), _deposit);
        //_setTokenBalance(address(WETH), address(syncBridge), wethDeposit, 3);
        deal(address(WETH), address(syncBridge), _ethDeposit);
        uint256 virtualNoteAmount;

        vm.startPrank(address(ROLLUP_PROCESSOR));

        {
            (uint256 outputValueA, , ) = syncBridge.convert(
                getRealAztecAsset(address(DAI)),
                emptyAsset,
                AztecTypes.AztecAsset({id: 1, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL}),
                emptyAsset,
                _deposit,
                1,
                0,
                address(0)
            );

            vm.stopPrank();

            uint256 bridgeDAI = DAI.balanceOf(address(syncBridge));
            virtualNoteAmount = outputValueA;

            assertEq(_deposit, bridgeDAI, "Balances must match");
        }

        {
            uint64 data;

            {
                (int24 _a, int24 _b) = _adjustTickParams(TickMath.MIN_TICK, TickMath.MAX_TICK, POOL);
                uint24 a = uint24(_a);
                uint24 b = uint24(_b);
                uint48 ticks = (uint48(a) << 24) | uint48(b);
                uint16 fee = 3000;
                data = (uint64(ticks) << 16) | uint64(fee);
            }

            vm.startPrank(address(ROLLUP_PROCESSOR));

            (uint256 callTwoOutputValueA, , ) = syncBridge.convert(
                AztecTypes.AztecAsset({id: 2, erc20Address: address(WETH), assetType: AztecTypes.AztecAssetType.ERC20}),
                AztecTypes.AztecAsset({id: 1, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL}),
                AztecTypes.AztecAsset({id: 2, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL}),
                AztecTypes.AztecAsset({id: 2, erc20Address: address(WETH), assetType: AztecTypes.AztecAssetType.ERC20}),
                _ethDeposit,
                2,
                data,
                address(0)
            );

            vm.stopPrank();

            uint256 callTwoVirtualNoteAmount = callTwoOutputValueA;

            (, , uint256 amount0, uint256 amount1, , , , , ) = syncBridge.getDeposit(2);

            (uint256 redeem0, uint256 redeem1) = _redeem(callTwoVirtualNoteAmount, 3);

            {
                //we set the margin of error to be 1/100,000 of the total initial size or .001%
                _marginOfError(amount0, redeem0, amount1, redeem1, 100000);
            }
        }
    }

    function testMintBySwap(uint256 _depositAmount) public {
        // revert();
        //506840802329476492815900036 is the point at which when the nonfungiblePositionManager's call to slot0() fails and the txn is reverted, presumably
        //because there is some sort of error in sqrtPriceX96 after the massive swap ? regardless this number is greater than several quadrillion DAI,
        //so i feel this is a logical upper boundary
        uint256 depositAmount = bound(_depositAmount, 1000000000000, 506840802329476492815900036);
        //_setTokenBalance(address(DAI), address(syncBridge), depositAmount, 2);
        deal(address(DAI), address(syncBridge), depositAmount);
        uint64 data;
        //pack params into data

        {
            /*
            IUniswapV3Pool pool = IUniswapV3Pool(IUniswapV3Factory(factory).getPool(address(DAI), address(WETH), 3000 ) );
            (uint160 sqrtPriceX96,,,,,,) = pool.slot0();
            int24 currentTick = TickMath.getTickAtSqrtRatio(sqrtPriceX96);
            */
            (int24 _a, int24 _b) = _adjustTickParams(TickMath.MIN_TICK, TickMath.MAX_TICK, POOL);
            uint24 a = uint24(_a);
            uint24 b = uint24(_b);
            uint48 ticks = (uint48(a) << 24) | uint48(b);
            uint16 fee = 3000;
            data = (uint64(ticks) << 16) | uint64(fee);
        }

        vm.startPrank(address(ROLLUP_PROCESSOR));

        (uint256 outputValueA, , ) = syncBridge.convert(
            getRealAztecAsset(address(DAI)),
            emptyAsset,
            AztecTypes.AztecAsset({id: 1, erc20Address: address(0), assetType: AztecTypes.AztecAssetType.VIRTUAL}),
            getRealAztecAsset(address(WETH)),
            depositAmount,
            1,
            data,
            address(0)
        );

        vm.stopPrank();

        (, , uint256 amount0, uint256 amount1, , , , , ) = syncBridge.getDeposit(1);

        (uint256 redeem0, uint256 redeem1) = _redeem(outputValueA, 2);

        _marginOfError(amount0, redeem0, amount1, redeem1, 100000 / 20);

        //Note (s)
        //at 25 million ethereum the .001 margin of error is breached
        //at 126 million eth the .005 MoE is breached
        //at 253 million eth the .01 MoE is breached
        //at 605 million eth the .05 MoE is breached
    }

    function _marginOfError(
        uint256 _amount0,
        uint256 _redeem0,
        uint256 _amount1,
        uint256 _redeem1,
        uint256 _marginFrac
    ) internal {
        //tests for rounding error

        //necessary when testing smaller values, which have larger margin % but are smaller in absolute terms
        //e.g. 1000 wei -> 999 wei, which is .1% error, very high

        //we dont care if the amount redeemed is more than the amount minted, only less than

        uint256 scale = 1000000;

        //sometimes when 1 output is much less than the input , the other output is much larger than its original input
        //e.g. token0 input of 100, output of 99, but token1 input of 100 and output of 101

        uint256 sum = ((_redeem0 * scale) / _amount0) + ((_redeem1 * scale) / _amount1);

        assertTrue(sum >= (2 * scale) - scale / _marginFrac, "not within %margin");
    }

    function _redeem(uint256 _inputValue, uint256 _nonce) internal returns (uint256, uint256) {
        AztecTypes.AztecAsset memory outputAssetA = AztecTypes.AztecAsset({
            id: _nonce,
            erc20Address: address(WETH),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        AztecTypes.AztecAsset memory outputAssetB = AztecTypes.AztecAsset({
            id: _nonce,
            erc20Address: address(DAI),
            assetType: AztecTypes.AztecAssetType.ERC20
        });

        vm.startPrank(address(ROLLUP_PROCESSOR));

        (uint256 outputValueA, uint256 outputValueB, ) = syncBridge.convert(
            AztecTypes.AztecAsset({
                id: _nonce - 1,
                erc20Address: address(0),
                assetType: AztecTypes.AztecAssetType.VIRTUAL
            }),
            AztecTypes.AztecAsset({
                id: _nonce,
                erc20Address: address(0),
                assetType: AztecTypes.AztecAssetType.NOT_USED
            }),
            outputAssetA,
            outputAssetB,
            _inputValue,
            _nonce,
            0,
            address(0)
        );
        vm.stopPrank();
        ///sort in terms of token0 or token1
        return (
            outputAssetA.erc20Address < outputAssetB.erc20Address
                ? (outputValueA, outputValueB)
                : (outputValueB, outputValueA)
        );
    }

    function _setTokenBalance(
        address _token,
        address _user,
        uint256 _balance,
        uint256 _slot
    ) internal {
        // May vary depending on token

        vm.store(_token, keccak256(abi.encode(_user, _slot)), bytes32(uint256(_balance)));

        assertEq(IERC20(_token).balanceOf(_user), _balance, "wrong balance");
    }

    function _adjustTickParams(
        int24 _tickLower,
        int24 _tickUpper,
        address _pool
    ) internal returns (int24 newTickLower, int24 newTickUpper) {
        //adjust the params s.t. they conform to tick spacing and do not fail the tick % tickSpacing == 0 check
        IUniswapV3Pool pool = IUniswapV3Pool(_pool);

        newTickLower = _tickLower % pool.tickSpacing() == 0
            ? _tickLower
            : _tickLower - (_tickLower % pool.tickSpacing());
        newTickUpper = _tickUpper % pool.tickSpacing() == 0
            ? _tickUpper
            : _tickUpper - (_tickUpper % pool.tickSpacing());
    }
}
