// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {ParentUniLPBridge, TransferHelper, ISwapRouter} from "./ParentUniLPBridge.sol";
import {IUniswapV3Pool} from "../../interfaces/uniswapv3/IUniswapV3Pool.sol";
import {IDefiBridge} from "../../aztec/interfaces/IDefiBridge.sol";
import {IQuoterV2} from "../../interfaces/uniswapv3/IQuoterV2.sol";
import {IQuoter} from "../../interfaces/uniswapv3/IQuoter.sol";
import {TickMath} from "../../libraries/uniswapv3/TickMath.sol";
import {FullMath} from "../../libraries/uniswapv3/FullMath.sol";
import {LiquidityAmounts} from "../../libraries/uniswapv3/LiquidityAmounts.sol";
import {ErrorLib} from "../base/ErrorLib.sol";

contract UniLPBridge is IDefiBridge, ParentUniLPBridge {
    using SafeERC20 for IERC20;

    error InvalidRefund();

    //used as a record for MINT_PT1 & MINT_P2
    struct MintFunding {
        address token;
        uint256 amount;
    }

    struct OptimalLiqParams {
        address token0;
        address token1;
        uint24 fee;
        uint256 amount0;
        uint256 amount1;
        uint160 sqrtRatioAX96;
        uint160 sqrtRatioBX96;
    }

    mapping(uint256 => MintFunding) public syncMintFundingMap; //interaction nonce -> MintFunding struct for MINT_PT1 interactions

    constructor(address _rollupProcessor) public ParentUniLPBridge(_rollupProcessor) {}

    /**
     * @notice  packs _auxData for front end user
     * @dev The first 24 bits are tickLower. The second 24 are tickUpper. The last 16 the pool's fee.
     * As a pool's fee ranges from 10 bps, 100 bps, 300 bps, and 1000 bps, there is no data loss and type conversion
     * is acceptable.
     * @param _tickLower the lower range of the position
     * @param _tickUpper the upper range of the position
     * @param _fee the fee tier of the pool
     * @return _auxData the packed _auxData
     */
    function packData(
        int24 _tickLower,
        int24 _tickUpper,
        uint24 _fee
    ) external view returns (uint64 _auxData) {
        uint24 a = uint24(_tickLower);
        uint24 b = uint24(_tickUpper);
        uint48 ticks = (uint48(a) << 24) | uint48(b);
        uint16 fee = uint16(_fee);
        _auxData = (uint64(ticks) << 16) | uint64(fee);
    }

    /**
     * @notice  Functions are used to unpack _auxData in chunks of 24 or 16 bits.
     * @dev The first 24 bits are tickLower. The second 24 are tickUpper. The last 16 the pool's fee.
     * As a pool's fee ranges from 10 bps, 100 bps, 300 bps, and 1000 bps, there is no data loss and type conversion
     * is acceptable.
     * @param _a The uint64 to be unpacked
     * @return b the uint24 or uint16
     */
    function unpackFirst24Bits(uint64 _a) public pure returns (uint24 b) {
        b = uint24(_a >> 40);
    }

    function unpackSecond24Bits(uint64 _a) public pure returns (uint24 b) {
        b = uint24(_a >> 16);
    }

    function unpackLast16Bits(uint64 _a) public pure returns (uint16 b) {
        b = uint16(_a);
    }

    /**
     * @notice This function performs 4 different types of interactions.
     * @dev  Step 1 of minting a liquidity position. Step 2 of minting a
     * liquidity position. The necessity of splitting this into two steps is necessitated by
     * the bridge's constraints (only 1 real asset input per convert call).
     * Lastly, redemption of liquidity for underlying. T
     * The interactions are completed in some cases within the function,
     *and sometimes by calls to internal functions where the logic is performed.
     * note: "Virtual" means virtual note, which represents ownership of an interaction nonce.
     * i.e. if you deposit some token in interaction 445 , you will receive a virtual note giving you ownership
     * of nonce 445 so that you may use the virtual note to reedem later. In the case of Minting Part 1
     * you receive a virtual note after depositing the first token in the pair you wish to LP for.
     * In Minting Part 2, you input your virtual note representing your deposited token, along with
     * the second token in the pair you wish to LP for. If the LP position is created successfully, you
     * will receive a virtual note giving ownership of LP position via the nonce.
     * At redemption, the virtual note is inputted and the LP position is redeemed.
     * Some considerations: In Minting Part 2, the refund is constrained to be the token deposited in
     * Minting Part 1, or inputAssetA's token. Additionally the token deposited in Minting Part1
     * should NOT be the same as the token input as inputAssetA in Minting Part 2.
     *                              Minting Part 1       Minting Part 2                 Redeeming
     * @param _inputAssetA -        ETH or ERC20         ETH or ERC20                   Virtual
     * @param _inputAssetB -        Unused               Virtual                        Unused
     * @param _outputAssetA -       Virtual              Virtual                        ETH or ERC20
     * @param _outputAssetB -       Unused               ETH or ERC20 (refund)          ETH or ERC20
     * @param _inputValue -         ETH or ERC20 amount  _inputAssetA amount            liquidity to be redeemed
     * @param _interactionNonce -   current nonce        current nonce                  current nonce
     * @param _auxData -            0                    tickLower, tickUpper, pool fee 0
     * @return outputValueA -       _inputValue          total liquidity of the position assetA amount redeemed
     * @return outputValueB -       0                    any amount refunded             assetB amount redeemed
     */
    function convert(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata _inputAssetB,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata _outputAssetB,
        uint256 _inputValue,
        uint256 _interactionNonce,
        uint64 _auxData,
        address
    )
        external
        payable
        override(IDefiBridge)
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool
        )
    {
        //require(inputValue == 0, "ZERO");

        if (msg.sender != address(ROLLUP_PROCESSOR)) revert ErrorLib.InvalidCaller();

        //INTERACTION TYPE 1
        //1 real 1 not used
        //1 virtual 1 not used

        if (
            _outputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED &&
            (_inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 ||
                _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) &&
            _inputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL
        ) {
            //sanity check
            address inputAddress = _handleETHReturnAddress(_inputAssetA);

            //state changes
            //deposit funds
            syncMintFundingMap[_interactionNonce] = MintFunding({token: inputAddress, amount: _inputValue});
            //_outputAssetA.id = _interactionNonce;
            //_outputAssetA.erc20Address = inputAddress;
            outputValueA = _inputValue;
        }
        //INTERACTION TYPE 2
        //1 real 1 virtual
        //1 virtual 1 real (refund)
        else if (
            _inputAssetB.assetType == AztecTypes.AztecAssetType.VIRTUAL &&
            (_inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 ||
                _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL &&
            (_outputAssetB.assetType == AztecTypes.AztecAssetType.ERC20 ||
                _outputAssetB.assetType == AztecTypes.AztecAssetType.ETH)
        ) {
            //minting LP position
            //sanity checks + variable instantiation
            address inputAddress = _handleETHReturnAddress(_inputAssetA);
            address refundAddress = _handleETHReturnAddress(_outputAssetB); // this asset is used for refunds

            //constrain refund to be one of the tokens
            if (!(inputAddress == refundAddress || refundAddress == syncMintFundingMap[_inputAssetB.id].token))
                revert InvalidRefund();

            (outputValueA, outputValueB) = _convertMintPart2(
                inputAddress,
                refundAddress,
                _interactionNonce,
                _inputAssetB.id,
                _inputValue,
                _auxData
            );
        }
        //INTERACTION TYPE 3
        //1 real 1 not used
        //1 virtual 1 real (the second pair)
        else if (
            _inputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED &&
            (_inputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 ||
                _inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL &&
            (_outputAssetB.assetType == AztecTypes.AztecAssetType.ERC20 ||
                _outputAssetB.assetType == AztecTypes.AztecAssetType.ETH)
        ) {
            //sanity check
            //note: _outputAssetB's address is assumed to be the secondary address necessary to retrieve the pool, but also for
            //any refunds , if necessary
            address inputAddress = _handleETHReturnAddress(_inputAssetA);
            address outputAddress = _handleETHReturnAddress(_outputAssetB);

            (outputValueA, outputValueB) = _convertMintBySwap(
                inputAddress,
                outputAddress,
                _interactionNonce,
                _inputValue,
                _auxData
            );
        }
        //INTERACTION TYPE 4
        //1 virtual 1 not used
        //1 real 1 real
        else if (
            (_outputAssetA.assetType == AztecTypes.AztecAssetType.ERC20 ||
                _outputAssetA.assetType == AztecTypes.AztecAssetType.ETH) &&
            _inputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED &&
            _inputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL &&
            (_outputAssetB.assetType == AztecTypes.AztecAssetType.ERC20 ||
                _outputAssetB.assetType == AztecTypes.AztecAssetType.ETH)
        ) {
            //withdrawing LP

            //sanity check
            uint256 id = _inputAssetA.id; //avoid stack too deep
            address tokenA = _handleETHReturnAddress(_outputAssetA);
            address tokenB = _handleETHReturnAddress(_outputAssetB);

            {
                // less storage reads
                address token0 = deposits[id].token0;
                address token1 = deposits[id].token1;
                //sanity check: constrain the outputs to equal the tokens of the actual LP position.
                bool validArgs = (tokenA == token0 && token1 == tokenB) || (tokenB == token0 && token1 == tokenA);
                if (!validArgs) revert InvalidOutputs();
            }

            //state changes
            //actual withdrawal via uniswap is done here
            (outputValueA, outputValueB) = _withdraw(id, uint128(_inputValue));
            //done because _decreaseLiquidity spits out amount0 amount1 and A && B not necessariy == token0 && token1
            if (!(tokenA == deposits[id].token0)) {
                (outputValueA, outputValueB) = (outputValueB, outputValueA);
            }

            //note: if the one of the tokens here is WETH, the rollupProcessor will
            //receive approval for the WETH amount but then also receive ETH in
            //receiveEthFromBridge. Proabbly not a problem but it's a sort of double counting of sorts?
            //worth noting

            TransferHelper.safeApprove(tokenA, address(ROLLUP_PROCESSOR), 0);
            TransferHelper.safeApprove(tokenB, address(ROLLUP_PROCESSOR), 0);
            TransferHelper.safeApprove(tokenA, address(ROLLUP_PROCESSOR), outputValueA);
            TransferHelper.safeApprove(tokenB, address(ROLLUP_PROCESSOR), outputValueB);

            if (_inputAssetA.assetType == AztecTypes.AztecAssetType.ETH) {
                WETH.withdraw(outputValueA);
                ROLLUP_PROCESSOR.receiveEthFromBridge{value: outputValueA}(_interactionNonce);
            } else if (_inputAssetB.assetType == AztecTypes.AztecAssetType.ETH) {
                WETH.withdraw(outputValueB);
                ROLLUP_PROCESSOR.receiveEthFromBridge{value: outputValueB}(_interactionNonce);
            }
        }
    }

    /**
     * @notice internal function to perform part 2 of the 2-step minting interaction
     * @dev performs some checks, unpacks the _params, then mints a new position. handles refunding at the end.
     * @param _input address of the input asset
     * @param _refund address of the output/refund asset
     * @param _interactionNonce the _interactionNonce
     * @param _id the _interactionNonce of the virtual asset provided in the convert call, which is used to prove ownersip
     * of an interaction that provided funding in step 1 for this step.
     * @param _inputValue the input size of _inputAssetA.
     * @param _params the _params, including the tickLower, the tickUpper, and the pool's fee.
     * @return outputValueA outputvalueA , liquidity minted
     * @return outputValueB outputvalueb, the refund
     */
    function _convertMintPart2(
        address _input,
        address _refund,
        uint256 _interactionNonce,
        uint256 _id,
        uint256 _inputValue,
        uint64 _params
    ) internal returns (uint256 outputValueA, uint256 outputValueB) {
        //no require check to make sure pool exists because uniswap will revert

        address[] memory token = new address[](2);

        {
            //avoid stack too deep and avoids 3 reads to storage
            address deposited = syncMintFundingMap[_id].token;
            token[0] = _input < deposited ? _input : deposited;
            token[1] = _input < deposited ? deposited : _input;
        }

        //state changes
        //_outputAssetA.id = _interactionNonce;

        uint24 fee;
        uint256 refund0;
        uint256 refund1;

        {
            //avoid stack too deep
            uint256 amount0 = token[0] == _input ? _inputValue : syncMintFundingMap[_id].amount;
            uint256 amount1 = token[0] == _input ? syncMintFundingMap[_id].amount : _inputValue;
            uint256 stackholderNonce = _interactionNonce;
            //outputValueA = liquidity here
            fee = uint24(unpackLast16Bits(_params));
            int24 tickLower = int24(unpackFirst24Bits(_params));
            int24 tickUpper = int24(unpackSecond24Bits(_params));
            (outputValueA, refund0, refund1) = _mintNewPosition(
                token[0],
                token[1],
                amount0,
                amount1,
                tickLower,
                tickUpper,
                fee,
                stackholderNonce
            );
        }

        //refunding
        if ((refund1 > 0 && _refund == token[0]) || (refund0 > 0 && _refund == token[1])) {
            outputValueB = token[0] == _refund ? refund0 : refund1;
            uint256 amountOut = _refundConversion(refund0, refund1, _refund, token[0], token[1], fee);
            outputValueB = outputValueB + amountOut;
            TransferHelper.safeApprove(_refund, address(ROLLUP_PROCESSOR), 0);
        }

        //we need to destroy record of MINT_PT1 funding to avoid virtual asset re-use
        syncMintFundingMap[_id].amount = 0;

        //approve rollupProcessor to receive refund
        TransferHelper.safeApprove(_refund, address(ROLLUP_PROCESSOR), outputValueB);
    }

    /**
     * @notice internal function to perform the mint-by-swap interaction
     * @dev swaps half of the input. Mints a new position, and handles refunding.
     * @param _input the input asset's address
     * @param _output the output asset's address
     * @param _interactionNonce the interaction nonce
     * @param _inputValue the size of the input asset
     * @param _params the _params for the liquidity position, i.e. tickLower, tickUpper, and the pool fee.
     * @return outputValueA the liquidity minted
     * @return outputValueB the refund if any
     */
    function _convertMintBySwap(
        address _input,
        address _output,
        uint256 _interactionNonce,
        uint256 _inputValue,
        uint64 _params
    ) internal returns (uint256 outputValueA, uint256 outputValueB) {
        uint256[] memory amounts = new uint256[](2);
        uint24 fee = uint24(unpackLast16Bits(_params));

        //swap half of input
        {
            TransferHelper.safeApprove(_input, address(SWAP_ROUTER), _inputValue / 2);
            ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
                tokenIn: _input,
                tokenOut: _output,
                fee: fee,
                recipient: address(this),
                deadline: block.timestamp,
                amountIn: _inputValue / 2,
                amountOutMinimum: 0, //flashbots
                sqrtPriceLimitX96: 0
            });

            uint256 amountOut = SWAP_ROUTER.exactInputSingle(swapParams);

            amounts[0] = _input < _output ? _inputValue / 2 : amountOut;
            amounts[1] = _input < _output ? amountOut : _inputValue / 2;
        }
        //_outputAssetA.id = _interactionNonce;
        uint256 refund0;
        uint256 refund1;
        address token0 = _input < _output ? _input : _output;
        address token1 = _input < _output ? _output : _input;

        {
            uint256 stackholderNonce = _interactionNonce; //avoid stack too deep
            int24 tickLower = int24(unpackFirst24Bits(_params));
            int24 tickUpper = int24(unpackSecond24Bits(_params));
            (outputValueA, refund0, refund1) = _mintNewPosition(
                token0,
                token1,
                amounts[0],
                amounts[1],
                tickLower,
                tickUpper,
                fee,
                stackholderNonce
            );
        }

        //refunding
        //due to bridge limitations only 1 token can be specified as the asset in which refunds are received
        //But a refund of two assets at the same time is possible and moreover we don't want the user to accidentally
        //specify token0 as the refund but all the refund is in token1 and they don't receive it.
        //so instead the bridge checks that any and all refunds are to be converted if necessary by swap
        //to the designated refund asset. it then adds to this outputValueB.
        //the defiBridgeProxy will call recoverTokens and the user should receive the refund.
        //this approach is naive and the user will incur slippage and fees as well. so it would be smarter
        //for them to simulate offchain to make sure they only receive a refund in one token or none.
        if ((refund1 > 0 && _output == token0) || (refund0 > 0 && _output == token1)) {
            outputValueB = token0 == _output ? refund0 : refund1;
            amounts[0] = _refundConversion(refund0, refund1, _output, token0, token1, fee);
            outputValueB = outputValueB + amounts[0];
            TransferHelper.safeApprove(_output, address(ROLLUP_PROCESSOR), 0);
        }

        TransferHelper.safeApprove(_output, address(ROLLUP_PROCESSOR), outputValueB);
    }

    function _calculateOptimal0Alternative(
        uint256 _deposit,
        uint256 _amountOut,
        uint160 _priceLower,
        uint160 _priceUpper,
        uint256 _supply,
        address _pool
    ) internal view returns (uint256) {
        //require that pricelower < price < priceupper
        //see https://atiselsts.github.io/pdfs/uniswap-v3-liquidity-math.pdf
        //page 3 subsection 3 , equation 10 for the derivation of this equation
        //let (sqrtP)(sqrtP_b)( sqrtP - sqrtP_a)/(sqrtP_b - sqrtP) = A
        //we have xA = y. we substitute y for (S-x) * r where r = ratio of token 1 / token0
        //then after substitution have xA = (S-x)r
        //solving for x we have x = Sr / (A +r)
        (uint160 sqrtPrice, , , , , , ) = IUniswapV3Pool(_pool).slot0();
        uint256 denominator = FullMath.mulDiv(sqrtPrice, _priceUpper, _priceUpper - sqrtPrice);
        denominator *= (sqrtPrice - _priceLower); //finish assembling A
        denominator = denominator / 2**96; //get rid of first 2**96 in A, every other unit cancels out now or later
        denominator += (_deposit * (2**96)) / _amountOut; //mul by 2**96 for floating point handling and match units w/ A
        //at this point we have denominator = A*(10^b-a)*2**96 + r*(10^b-a)*2**96
        uint256 numerator = FullMath.mulDiv(_supply, _deposit, _amountOut) * 2**96;
        //numerator = Sr * (10^b)*2**96
        //at this point the 2**96 will cancel out, and the 10^b / 10 ^ b-a = 10^a
        //resulting in the application of our desired unit/scalar
        //to produce optimal token0 qty with correct decimals
        return FullMath.mulDiv(numerator, 1, denominator);
    }

    function optimizeLiquidity(OptimalLiqParams memory _params) external returns (uint256, uint256) {
        uint256 amountOut;
        (uint160 originalPrice, , , , , , ) = IUniswapV3Pool(
            UNISWAP_FACTORY.getPool(_params.token0, _params.token1, _params.fee)
        ).slot0();

        {
            //we are doing this by token0 (weth in this case)
            //so we swap token1 to token0
            //WETH is token0 and is also high priced. as we sell USDT price will increase.
            //therefore our price limit if the max.
            IQuoter quoter = IQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
            amountOut = quoter.quoteExactInputSingle(
                _params.token1,
                _params.token0,
                _params.fee,
                _params.amount1,
                (originalPrice * 1000) / 100
            );
        }
        uint256 optimal0 = _calculateOptimal0Alternative(
            _params.amount1, //token1 amount to be used for r , which is token1 qty / amountOut
            amountOut, //amountOut , to be used for r, which is token1 qty/ amountOut
            _params.sqrtRatioAX96, //priceLower
            _params.sqrtRatioBX96, //priceUpper
            amountOut + _params.amount0, //supply, S term in Sr/(A+r), calculatd as amountOut+ initial token0 qty
            UNISWAP_FACTORY.getPool(_params.token0, _params.token1, _params.fee) //pool, used to calculate current sqrtPriceX96
        );

        uint256 amountIn;
        //token[0] is tokenIn NOT token0 token[1] is tokenOut NOT token1
        address[] memory token = new address[](2);
        {
            bool flag = _params.amount0 < optimal0;
            //if flag true
            //we need to sell token1 to get more token0
            //gives us token1 amount we need to sell
            amountIn = flag
                ? ((optimal0 - _params.amount0) * _params.amount1) / amountOut
                : (_params.amount0 - optimal0);
            token[0] = flag ? _params.token1 : _params.token0;
            token[1] = flag ? _params.token0 : _params.token1;
        }

        uint160 sqrtPriceX96After;

        {
            //we are doing this by token0 (weth in this case)
            //so we swap token1 to token0
            //WETH is token0 and is also high priced. as we sell USDT price will increase.
            //therefore our price limit if the max.

            IQuoterV2 quoter = IQuoterV2(0x61fFE014bA17989E743c5F6cB21bF9697530B21e);
            (amountOut, sqrtPriceX96After, , ) = quoter.quoteExactInputSingle(
                IQuoterV2.QuoteExactInputSingleParams({
                    tokenIn: token[0],
                    tokenOut: token[1],
                    fee: _params.fee,
                    amountIn: amountIn,
                    //intuitively we don't want price to move out of our range
                    sqrtPriceLimitX96: token[0] < token[1] ? _params.sqrtRatioAX96 : _params.sqrtRatioBX96
                })
            );
        }
        //note: depending on which token was meant to be swapped in, we net the balances
        //if liquiditybefore > liquidityafter
        if (
            uint256(
                LiquidityAmounts.getLiquidityForAmounts(
                    sqrtPriceX96After,
                    _params.sqrtRatioAX96,
                    _params.sqrtRatioBX96,
                    token[0] == _params.token0 ? _params.amount0 - amountIn : _params.amount0 + amountOut,
                    token[0] == _params.token1 ? _params.amount1 - amountIn : _params.amount1 + amountOut
                )
            ) <
            uint256(
                LiquidityAmounts.getLiquidityForAmounts(
                    originalPrice,
                    _params.sqrtRatioAX96,
                    _params.sqrtRatioBX96,
                    _params.amount0,
                    _params.amount1
                )
            )
        ) {
            //IF WE REACH THIS, OUR OPTIMIZATION FAILED, WE USE INITIAL ARGS INSTEAD
            return (_params.amount0, _params.amount1);
        } else if (amountIn > 0) {
            //OPTIMIZATION SUCCEEDED
            //see above note preceding getLiquidityForAmounts calls on why we use _params.amount0+amountOut
            //rather than using optimal0
            return (
                token[0] == _params.token0 ? _params.amount0 - amountIn : _params.amount0 + amountOut,
                token[0] == _params.token1 ? _params.amount1 - amountIn : _params.amount1 + amountOut
            );
        }

        return (_params.amount0, _params.amount1);
    }

    function finalise(
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        AztecTypes.AztecAsset calldata,
        uint256,
        uint64
    )
        external
        payable
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool interactionComplete
        )
    {
        revert ErrorLib.AsyncDisabled();
    }
}
