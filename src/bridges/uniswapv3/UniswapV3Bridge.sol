pragma solidity >=0.6.10 <=0.8.10;

import {SafeMath} from "../../../node_modules/@openzeppelin/contracts/utils/math/SafeMath.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "../../interfaces/IRollupProcessor.sol";
import "./interfaces/IUniswapV3Factory.sol";
import "./base/LiquidityManagement.sol";
import "./interfaces/IWETH9.sol";

contract UniswapV3Bridge is LiquidityManagement, IERC721Receiver {
    using SafeMath for uint256;

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

    mapping(uint256 => Deposit) public deposits; //interaction nonce -> deposit struct

    /* 
        IMMUTABLE VARIABLES
    */

    address public immutable owner;
    IRollupProcessor public immutable rollupProcessor;
    ISwapRouter public immutable swapRouter;
    INonfungiblePositionManager public immutable nonfungiblePositionManager;
    IUniswapV3Factory public immutable uniswapFactory;
    IWETH9 public immutable WETH;

    /* 
        NOT USED IN PRODUCTION, FOR TESTING PURPOSES ONLY
    */

    //bytes public originalCode;

    constructor(
        address _rollupProcessor,
        address _router,
        address _nonfungiblePositionManager,
        address _factory,
        address _WETH
    ) public PeripheryImmutableState(_factory, _WETH) {
        nonfungiblePositionManager = INonfungiblePositionManager(_nonfungiblePositionManager);
        rollupProcessor = IRollupProcessor(_rollupProcessor);
        swapRouter = ISwapRouter(_router);
        WETH = IWETH9(_WETH);
        uniswapFactory = IUniswapV3Factory(_factory);
        owner = msg.sender;
    }

    function onERC721Received(
        address operator,
        address,
        uint256 tokenId,
        bytes calldata
    ) external override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @notice  gets the present value of a position
     * @dev gets the value of a position by converting liquidity to expected amounts using uniswap helper fxns
     * we use this way because deposits.amount0 and deposits.amount1 might return positive for an interaction that
     * is finalised or no longer live, and nonfungiblepositionamanger.positions() doesn't return an amount0 or amount1, only liquidity
     * @param interactionNonce the interactionNonce of the specific interaction in question
     * @return amount0 the shalf of the position's value in token0 terms
     * @return amount1 the half of the position's value in token1 terms
     */

    function getPresentValue(uint256 interactionNonce) external view returns (uint256 amount0, uint256 amount1) {
        uint256 tokenId = deposits[interactionNonce].tokenId;

        //calculate using LIquidityAmounts.sol library
        uint160 sqrtPriceX96;

        {
            IUniswapV3Pool pool = IUniswapV3Pool(
                uniswapFactory.getPool(
                    deposits[interactionNonce].token0,
                    deposits[interactionNonce].token0,
                    deposits[interactionNonce].fee
                )
            );

            (sqrtPriceX96, , , , , , ) = pool.slot0();
        }

        (amount0, amount1) = LiquidityAmounts.getAmountsForLiquidity(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(deposits[interactionNonce].tickLower),
            TickMath.getSqrtRatioAtTick(deposits[interactionNonce].tickUpper),
            deposits[interactionNonce].liquidity
        );
    }

    /**
     * @notice  gets the liquidity in a specific tick range within a pool
     * @dev we are concerned with the specific liquidity of a tick range, not the overall liquidity.
     * Uniswap pools do not provide this as a public variable unlike overall liquidity but we can calculate it
     * by using tickBitmap which provides the liquidity of a specific tick. we simply iterate over the user's defined tick range
     * and sum up the liquidity
     * @param tokenA the first token (not necessarily token0)
     * @param tokenB the second token
     * @param auxData auxdata containing ticklower, tickupper, and fee tier of pool
     * @return balance0 liquidity in terms of token0
     * @return balance1 liquidity in terms of token1
     */

    function getLiquidity(
        address tokenA,
        address tokenB,
        uint64 auxData
    ) external view returns (uint256 balance0, uint256 balance1) {
        uint24 fee = uint24(uint16(auxData));
        int24 tickLower = int24(uint24(auxData >> 40));
        int24 tickUpper = int24(uint24(auxData >> 16));
        address pool = uniswapFactory.getPool(tokenA, tokenB, fee);
        int24 tickSpacing = IUniswapV3Pool(pool).tickSpacing();
        uint128 liquidity = 0;

        require(tickLower % tickSpacing == 0 && tickUpper % tickSpacing == 0, "SPACING");

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
     * @param interactionNonce the nonce of the interaction
     * @return Deposit the deposit/ its contents
     */

    function getDeposit(uint256 interactionNonce)
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
        Deposit memory deposit = deposits[interactionNonce];

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
     * @notice  Function handle tether transfers
     * @dev if tether transfer and nonzero transfer/approval, set approval to 0 first, then set second approval
     * @param token the token being transferred/approved
     * @param to the address to transfer to
     * @param value the amount transferred/approved
     */

    function ERC20NoReturnApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        if (token == 0xdAC17F958D2ee523a2206206994597C13D831ec7 && value != 0) {
            TransferHelper.safeApprove(token, to, 0);
        }

        TransferHelper.safeApprove(token, to, value);
    }

    /**
     * @notice  Function used to withdraw liquidity
     * @dev also handles bridge accounting.
     * note that the bridge accounting only subtracts liquidity
     * but does not subtract deposits[interactionnonce].amount0, so thes amounts will always be positive
     * hence we do not rely on them as indicators of liquidity
     * @param interactionNonce the nonce of the interaction
     * @param liquidity the amount of liquidity to be withdrawn
     * @return withdraw0 the amount of token0 received
     * @return withdraw1 the amount of token1 received
     */

    function _withdraw(uint256 interactionNonce, uint128 liquidity)
        internal
        returns (uint256 withdraw0, uint256 withdraw1)
    {
        // get liquidity data for tokenId
        // amount0Min and amount1Min are price slippage checks
        // if the amount received after burning is not greater than these minimums, transaction will fail
        //console.log(liquidity, "input liq");

        INonfungiblePositionManager.DecreaseLiquidityParams memory params = INonfungiblePositionManager
            .DecreaseLiquidityParams({
                tokenId: deposits[interactionNonce].tokenId,
                liquidity: liquidity,
                amount0Min: 0,
                amount1Min: 0,
                deadline: block.timestamp
            });

        (uint256 amount0Out, uint256 amount1Out) = nonfungiblePositionManager.decreaseLiquidity(params);

        //console.log(amount0Out, amount1Out, "decrease");

        {
            (withdraw0, withdraw1) = _collect(
                deposits[interactionNonce].tokenId,
                uint128(amount0Out),
                uint128(amount1Out)
            );

            //take care of dust
            //_sweepDust(interactionNonce, amount0Out, amount1Out, redeemed0, redeemed1);
        }

        //send liquidity back to owner
        //_approveTo(interactionNonce, amount0, amount1, address(rollupProcessor) );
        //bridge accounting

        require(deposits[interactionNonce].liquidity >= liquidity, "!GTE");
        deposits[interactionNonce].liquidity = deposits[interactionNonce].liquidity - liquidity;

        //decided this is irrelevant, as it triggers arithmetic overflow often, because in certain scenarios, amount0 is less
        //than amount0Out. for example if ETH price went up in DAI alot, then it could trigger the error.further more,
        //the bridges does not use amount0 or amount1 in deposits mapping for much.
        //deposits[interactionNonce].amount0 =  deposits[interactionNonce].amount0 > amount0Out ? deposits[interactionNonce].amount0- ;
        //deposits[interactionNonce].amount1 = deposits[interactionNonce].amount1.sub(amount1Out);
        //we use the following instead, which is used by asyncbridge as a record of how much output the position received
        //after withdrawal.

        deposits[interactionNonce].amount0 = withdraw0;
        deposits[interactionNonce].amount1 = withdraw1;
    }

    /**
     * @notice  collects the tokens after they are burned in _withdraw via decreaseliquidity
     * @param tokenId tokenId of the nft position
     * @param in0 the amount of token0 to be collected
     * @param in1 the amount of token1 to be collected
     * @return amount0 amount0 actually collected
     * @return amount1 amount1 actually collected
     */

    function _collect(
        uint256 tokenId,
        uint128 in0,
        uint128 in1
    ) internal returns (uint256 amount0, uint256 amount1) {
        // Caller must own the ERC721 position
        // set amount0Max and amount1Max to uint256.max to collect all fees
        // alternatively can set recipient to msg.sender and avoid another transaction in `sendToOwner`
        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId,
            recipient: address(this),
            amount0Max: in0,
            amount1Max: in1
        });

        (amount0, amount1) = nonfungiblePositionManager.collect(params);
        //console.log(amount0, amount1, "collect");
    }

    function _approveTo(
        uint256 interactionNonce,
        uint256 amount0,
        uint256 amount1,
        address _to
    ) internal {
        address token0 = deposits[interactionNonce].token0;
        address token1 = deposits[interactionNonce].token1;
        TransferHelper.safeApprove(token0, _to, amount0);
        TransferHelper.safeApprove(token1, _to, amount1);
    }

    /**
     * @notice  Function used to get a deposit
     * @dev creates the deposit for a new position , used by internal bridge accounting
     * @param tokenId tokenid of the nft position
     * @param interactionNonce the interaction nonce
     * @param amount0 the amount0 liquidity minted
     * @param amount1 the amount1 liquidity minted
     * @param fee the fee of the pool
     */

    function _createDeposit(
        uint256 tokenId,
        uint256 interactionNonce,
        uint256 amount0,
        uint256 amount1,
        uint24 fee
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

        ) = nonfungiblePositionManager.positions(tokenId);

        // set data for position
        deposits[interactionNonce] = Deposit({
            tokenId: tokenId,
            liquidity: liquidity,
            amount0: amount0,
            amount1: amount1,
            tickLower: tickLower,
            tickUpper: tickUpper,
            fee: fee,
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
        address token0,
        address token1,
        uint256 amount0ToMint,
        uint256 amount1ToMint,
        int24 tickLower,
        int24 tickUpper,
        uint24 fee,
        uint256 interactionNonce
    )
        internal
        returns (
            uint128 liquidity,
            uint256 refund0,
            uint256 refund1
        )
    {
        ERC20NoReturnApprove(token0, address(nonfungiblePositionManager), amount0ToMint);
        ERC20NoReturnApprove(token1, address(nonfungiblePositionManager), amount1ToMint);
        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: fee,
            tickLower: tickLower,
            tickUpper: tickUpper,
            amount0Desired: amount0ToMint,
            amount1Desired: amount1ToMint,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp
        });

        uint256 amount0;
        uint256 amount1;

        //console.log("reached minting");

        {
            uint256 tokenId;
            (tokenId, liquidity, amount0, amount1) = nonfungiblePositionManager.mint(params);
            //console.log(amount0, amount1, "mint");
            //console.log("passed minting");
            _createDeposit(tokenId, interactionNonce, amount0, amount1, fee);
            //console.log("passed deposit creation");
        }

        //console.log("reached refunding");
        // Remove allowance and refund in both assets.
        if (amount0 < amount0ToMint) {
            TransferHelper.safeApprove(token0, address(nonfungiblePositionManager), 0);
            refund0 = amount0ToMint - amount0;
            //TransferHelper.safeTransfer(token0, rollupProcessor, refund0);
        }

        if (amount1 < amount1ToMint) {
            TransferHelper.safeApprove(token1, address(nonfungiblePositionManager), 0);
            refund1 = amount1ToMint - amount1;
            //TransferHelper.safeTransfer(token1, rollupProcessor, refund1);
        }
    }

    /**
     * @notice converts any refunds in token0 or token1 to a refund token(0 or 1)
     * @dev if we have refunds in token 0 or 1 we need to conver all to 0 or all to 1.
     * this is due to the fact that the brige can only have 2 real outputs, and 1 output slot is occupied by the virtual
     * asset represneting the position itself. so if we have refunds in both tokens, one token's refund must be swapped to
     * have the refund all in one token
     * @param refund0 any refunds in token0
     * @param refund1 any refunds in token1
     * @param refund_address address of the refund token (0 or 1)
     * @param token0 token0 address
     * @param token1 token1 addr
     * @param fee fee
     * @return refundedAmount the refund amount after swapping superfluous refunds
     */

    function _refundConversion(
        uint256 refund0,
        uint256 refund1,
        address refund_address,
        address token0,
        address token1,
        uint24 fee
    ) internal returns (uint256 refundedAmount) {
        //we have refunds in token1, convert to token0 to match outputAssetB
        //or we have refunds in token0, convert to token1 to match outputAssetB
        // The call to `exactInputSingle` executes the swap.
        uint256 amountIn = refund_address == token0 ? refund1 : refund0;
        address tokenIn = refund_address == token0 ? token1 : token0;

        ERC20NoReturnApprove(tokenIn, address(swapRouter), amountIn);
        ISwapRouter.ExactInputSingleParams memory swap_params = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: refund_address == token0 ? token0 : token1,
            fee: fee,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: amountIn,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        //console.log("b4 swap");
        refundedAmount = swapRouter.exactInputSingle(swap_params);
        //console.log(refundedAmount, "refund");

        ERC20NoReturnApprove(tokenIn, address(swapRouter), 0);
    }

    //helper functions to peform testing/emergency measures

    function call(
        address payable _to,
        uint256 _value,
        bytes calldata _data
    ) external payable returns (bytes memory) {
        require(msg.sender == owner, "ONLY OWNER");
        require(_to != address(0));
        (bool _success, bytes memory _result) = _to.call{value: _value}(_data);
        require(_success);
        return _result;
    }

    function delegatecall(address payable _to, bytes calldata _data) external payable returns (bytes memory) {
        require(msg.sender == owner, "ONLY OWNER");
        require(_to != address(0));
        (bool _success, bytes memory _result) = _to.delegatecall(_data);
        require(_success);
        return _result;
    }

    function staticcall(address _to, bytes calldata _data) external view returns (bytes memory) {
        (bool _success, bytes memory _result) = _to.staticcall(_data);
        return _result;
    }
}
