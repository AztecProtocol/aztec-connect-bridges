// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {IRollupProcessor} from "../../aztec/interfaces/IRollupProcessor.sol";
import {IQuoter} from "../../interfaces/uniswapv3/IQuoter.sol";
import {INonfungiblePositionManager} from "../../interfaces/uniswapv3/INonfungiblePositionManager.sol";
import {IUniswapV3Factory} from "../../interfaces/uniswapv3/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "../../interfaces/uniswapv3/IUniswapV3Pool.sol";
import {ISwapRouter} from "../../interfaces/uniswapv3/ISwapRouter.sol";
import {IWETH9} from "../../interfaces/uniswapv3/IWETH9.sol";

import {PeripheryImmutableState} from "../../interfaces/uniswapv3/base/PeripheryImmutableState.sol";
import {LiquidityManagement} from "../../interfaces/uniswapv3/base/LiquidityManagement.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {LiquidityAmounts} from "../../libraries/uniswapv3/LiquidityAmounts.sol";
import {TransferHelper} from "../../libraries/uniswapv3/TransferHelper.sol";
import {TickMath} from "../../libraries/uniswapv3/TickMath.sol";

contract ParentUniLPBridge is LiquidityManagement, IERC721Receiver {
    using SafeERC20 for IERC20;

    struct Deposit {
        uint256 tokenId;
        uint128 liquidity;
        uint256 amount0;
        uint256 amount1;
        int24 tickLower;
        int24 tickUpper;
        uint24 fee;
        address token0;
        address token1;
    }

    error IncorrectSpacing();
    error InsufficientLiquidity();
    error InvalidOutputs();

    mapping(uint256 => Deposit) public deposits; //interaction nonce -> deposit struct

    IRollupProcessor public immutable ROLLUP_PROCESSOR;
    ISwapRouter public immutable SWAP_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    INonfungiblePositionManager public immutable NONFUNGIBLE_POSITION_MANAGER =
        INonfungiblePositionManager(0xC36442b4a4522E871399CD717aBDD847Ab11FE88);
    IUniswapV3Factory public immutable UNISWAP_FACTORY = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    IWETH9 public immutable WETH = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

    constructor(address _rollupProcessor) public PeripheryImmutableState(address(UNISWAP_FACTORY), address(WETH)) {
        ROLLUP_PROCESSOR = IRollupProcessor(_rollupProcessor);
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external override(IERC721Receiver) returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @notice  gets the present value of a position
     * @dev gets the value of a position by converting liquidity to expected amounts using uniswap helper fxns
     * we use this way because deposits.amount0 and deposits.amount1 might return positive for an interaction that
     * is finalised or no longer live, and nonfungiblepositionamanger.positions() doesn't return an amount0 or amount1, only liquidity
     * @param _interactionNonce the interactionNonce of the specific interaction in question
     * @return amount0 the shalf of the position's value in token0 terms
     * @return amount1 the half of the position's value in token1 terms
     */
    function getPresentValue(uint256 _interactionNonce) external view returns (uint256 amount0, uint256 amount1) {
        //calculate using LIquidityAmounts.sol library
        uint160 sqrtPriceX96;

        {
            IUniswapV3Pool pool = IUniswapV3Pool(
                UNISWAP_FACTORY.getPool(
                    deposits[_interactionNonce].token0,
                    deposits[_interactionNonce].token0,
                    deposits[_interactionNonce].fee
                )
            );

            (sqrtPriceX96, , , , , , ) = pool.slot0();
        }

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(deposits[_interactionNonce].tickLower),
            TickMath.getSqrtRatioAtTick(deposits[_interactionNonce].tickUpper),
            deposits[_interactionNonce].liquidity
        );
    }

    /**
     * @notice  gets the liquidity in a specific tick range within a pool
     * @dev we are concerned with the specific liquidity of a tick range, not the overall liquidity.
     * Uniswap pools do not provide this as a public variable unlike overall liquidity but we can calculate it
     * by using tickBitmap which provides the liquidity of a specific tick. we simply iterate over the user's defined tick range
     * and sum up the liquidity
     * @param _tokenA the first token (not necessarily token0)
     * @param _tokenB the second token
     * @param _auxData auxdata containing ticklower, tickupper, and fee tier of pool
     * @return balance0 liquidity in terms of token0
     * @return balance1 liquidity in terms of token1
     */
    function getLiquidity(
        address _tokenA,
        address _tokenB,
        uint64 _auxData
    ) external view returns (uint256 balance0, uint256 balance1) {
        uint24 fee = uint24(uint16(_auxData));
        int24 tickLower = int24(uint24(_auxData >> 40));
        int24 tickUpper = int24(uint24(_auxData >> 16));
        address pool = UNISWAP_FACTORY.getPool(_tokenA, _tokenB, fee);
        int24 tickSpacing = IUniswapV3Pool(pool).tickSpacing();
        uint128 liquidity = 0;

        if (tickLower % tickSpacing != 0 && tickUpper % tickSpacing != 0) revert IncorrectSpacing();

        for (int24 i = tickLower; i <= tickUpper; i += tickSpacing) {
            (uint128 liquidityGross, , , , , , , ) = IUniswapV3Pool(pool).ticks(i);

            liquidity += liquidityGross;
        }

        (uint160 sqrtPriceX96, , , , , , ) = IUniswapV3Pool(pool).slot0();

        (balance0, balance1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            liquidity
        );
    }

    /**
     * @notice  Function used to get a deposit
     * @dev gets a deposit
     * @param _interactionNonce the nonce of the interaction
     * @return Deposit the deposit/ its contents
     */
    function getDeposit(uint256 _interactionNonce)
        external
        view
        returns (
            uint256,
            uint128,
            uint256,
            uint256,
            int24,
            int24,
            uint24,
            address,
            address
        )
    {
        Deposit memory deposit = deposits[_interactionNonce];

        return (
            deposit.tokenId,
            deposit.liquidity,
            deposit.amount0,
            deposit.amount1,
            deposit.tickLower,
            deposit.tickUpper,
            deposit.fee,
            deposit.token0,
            deposit.token1
        );
    }

    /**
     * @notice  Function used to withdraw liquidity
     * @dev also handles bridge accounting.
     * note that the bridge accounting only subtracts liquidity
     * but does not subtract deposits[interactionnonce].amount0, so thes amounts will always be positive
     * hence we do not rely on them as indicators of liquidity
     * @param _interactionNonce the nonce of the interaction
     * @param _liquidity the amount of liquidity to be withdrawn
     * @return withdraw0 the amount of token0 received
     * @return withdraw1 the amount of token1 received
     */
    function _withdraw(uint256 _interactionNonce, uint128 _liquidity)
        internal
        returns (uint256 withdraw0, uint256 withdraw1)
    {
        // get liquidity data for tokenId
        // amount0Min and amount1Min are price slippage checks
        // if the amount received after burning is not greater than these minimums, transaction will fail

        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
                tokenId: deposits[_interactionNonce].tokenId,
                liquidity: _liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        (uint256 amount0Out, uint256 amount1Out) = NONFUNGIBLE_POSITION_MANAGER.decreaseLiquidity(params);

        {
            (withdraw0, withdraw1) = _collect(
                deposits[_interactionNonce].tokenId,
                uint128(amount0Out),
                uint128(amount1Out)
            );
        }

        if (deposits[_interactionNonce].liquidity < _liquidity) revert InsufficientLiquidity();
        deposits[_interactionNonce].liquidity = deposits[_interactionNonce].liquidity - _liquidity;

        //decided this is irrelevant, as it triggers arithmetic overflow often, because in certain scenarios, amount0 is less
        //than amount0Out. for example if ETH price went up in DAI alot, then it could trigger the error.further more,
        //the bridges does not use amount0 or amount1 in deposits mapping for much.
        //we use the following instead, which is used by asyncbridge as a record of how much output the position received
        //after withdrawal.

        deposits[_interactionNonce].amount0 = withdraw0;
        deposits[_interactionNonce].amount1 = withdraw1;
    }

    /**
     * @notice  collects the tokens after they are burned in _withdraw via decreaseliquidity
     * @param _tokenId tokenId of the nft position
     * @param _in0 the amount of token0 to be collected
     * @param _in1 the amount of token1 to be collected
     * @return amount0 amount0 actually collected
     * @return amount1 amount1 actually collected
     */
    function _collect(
        uint256 _tokenId,
        uint128 _in0,
        uint128 _in1
    ) internal returns (uint256 amount0, uint256 amount1) {
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: _tokenId,
            recipient: address(this),
            amount0Max: _in0,
            amount1Max: _in1
        });

        (amount0, amount1) = NONFUNGIBLE_POSITION_MANAGER.collect(params);
    }

    /**
     * @notice  Function used to get a deposit
     * @dev creates the deposit for a new position , used by internal bridge accounting
     * @param _tokenId tokenid of the nft position
     * @param _interactionNonce the interaction nonce
     * @param _amount0 the amount0 liquidity minted
     * @param _amount1 the amount1 liquidity minted
     * @param _fee the fee of the pool
     */
    function _createDeposit(
        uint256 _tokenId,
        uint256 _interactionNonce,
        uint256 _amount0,
        uint256 _amount1,
        uint24 _fee
    ) internal {
        (
            ,
            ,
            address token0,
            address token1,
            ,
            int24 tickLower,
            int24 tickUpper,
            uint128 liquidity,
            ,
            ,
            ,

        ) = NONFUNGIBLE_POSITION_MANAGER.positions(_tokenId);

        // set data for position
        deposits[_interactionNonce] = Deposit({
            tokenId: _tokenId,
            liquidity: liquidity,
            amount0: _amount0,
            amount1: _amount1,
            tickLower: tickLower,
            tickUpper: tickUpper,
            fee: _fee,
            token0: token0,
            token1: token1
        });
    }

    /**
     * @notice  mints a new position
     * @dev mints a new position, and creates a new deposit
     * @return liquidity the liquidty minted
     * @return refund0 any refunds in token0
     * @return refund1 any refunds in token1
     */
    function _mintNewPosition(
        address _token0,
        address _token1,
        uint256 _amount0ToMint,
        uint256 _amount1ToMint,
        int24 _tickLower,
        int24 _tickUpper,
        uint24 _fee,
        uint256 _interactionNonce
    )
        internal
        returns (
            uint128 liquidity,
            uint256 refund0,
            uint256 refund1
        )
    {
        TransferHelper.safeApprove(_token0, address(NONFUNGIBLE_POSITION_MANAGER), _amount0ToMint);
        TransferHelper.safeApprove(_token1, address(NONFUNGIBLE_POSITION_MANAGER), _amount1ToMint);
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: _token0,
            token1: _token1,
            fee: _fee,
            tickLower: _tickLower,
            tickUpper: _tickUpper,
            amount0Desired: _amount0ToMint,
            amount1Desired: _amount1ToMint,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        uint256 amount0;
        uint256 amount1;

        {
            uint256 tokenId;
            (tokenId, liquidity, amount0, amount1) = NONFUNGIBLE_POSITION_MANAGER.mint(params);
            _createDeposit(tokenId, _interactionNonce, amount0, amount1, _fee);
        }

        // Remove allowance and refund in both assets.
        if (amount0 < _amount0ToMint) {
            TransferHelper.safeApprove(_token0, address(NONFUNGIBLE_POSITION_MANAGER), 0);
            refund0 = _amount0ToMint - amount0;
            //TransferHelper.safeTransfer(token0, rollupProcessor, refund0);
        }

        if (amount1 < _amount1ToMint) {
            TransferHelper.safeApprove(_token1, address(NONFUNGIBLE_POSITION_MANAGER), 0);
            refund1 = _amount1ToMint - amount1;
            //TransferHelper.safeTransfer(token1, rollupProcessor, refund1);
        }
    }

    /**
     * @notice converts any refunds in token0 or token1 to a refund token(0 or 1)
     * @dev if we have refunds in token 0 or 1 we need to conver all to 0 or all to 1.
     * this is due to the fact that the brige can only have 2 real outputs, and 1 output slot is occupied by the virtual
     * asset represneting the position itself. so if we have refunds in both tokens, one token's refund must be swapped to
     * have the refund all in one token
     * @param _refund0 any refunds in token0
     * @param _refund1 any refunds in token1
     * @param _refundAddress address of the refund token (0 or 1)
     * @param _token0 token0 address
     * @param _token1 token1 addr
     * @param _fee fee
     * @return refundedAmount the refund amount after swapping superfluous refunds
     */
    function _refundConversion(
        uint256 _refund0,
        uint256 _refund1,
        address _refundAddress,
        address _token0,
        address _token1,
        uint24 _fee
    ) internal returns (uint256 refundedAmount) {
        //we have refunds in token1, convert to token0 to match outputAssetB
        //or we have refunds in token0, convert to token1 to match outputAssetB
        // The call to `exactInputSingle` executes the swap.
        uint256 amountIn = _refundAddress == _token0 ? _refund1 : _refund0;
        address tokenIn = _refundAddress == _token0 ? _token1 : _token0;
        TransferHelper.safeApprove(tokenIn, address(SWAP_ROUTER), 0);
        TransferHelper.safeApprove(tokenIn, address(SWAP_ROUTER), amountIn);
        //check balances next step
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: _refundAddress,
            fee: _fee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: tokenIn == _token0 ? 0 : type(uint160).max / 1000000
        });
        refundedAmount = SWAP_ROUTER.exactInputSingle(swapParams);

        TransferHelper.safeApprove(tokenIn, address(SWAP_ROUTER), 0);
    }

    /**
     * @notice this function is used to check whether an AztecAsset is an ERC20 or ETH.
     * @dev If it is ETH,
     * then the underlying ETH is wrapped and the function returns the WETH address (since inputAsset.erc20Address returns 0 if
     * the underlying is ETH).
     * @param _inputAsset The Aztec input asset
     * @return address the address of the asset, WETH if it is ETH, else erc20 address
     */
    function _handleETHReturnAddress(AztecTypes.AztecAsset calldata _inputAsset) internal returns (address) {
        if (_inputAsset.assetType == AztecTypes.AztecAssetType.ETH) {
            WETH.deposit{value: address(this).balance}();
            return address(WETH);
        } else {
            return _inputAsset.erc20Address;
        }
    }
}
