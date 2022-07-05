// SPDX-License-Identifier: Apache-2.0
// Copyright 2022 Aztec.
pragma solidity >=0.8.4;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import {AztecTypes} from "../../aztec/libraries/AztecTypes.sol";
import {UniswapV3Bridge, TransferHelper, ISwapRouter} from "./UniswapV3Bridge.sol";
import {IUniswapV3Pool} from "./interfaces/IUniswapV3Pool.sol";
import {IDefiBridge} from "../../aztec/interfaces/IDefiBridge.sol";
import {console} from "../../../lib/forge-std/src/console.sol";

contract SyncUniswapV3Bridge is IDefiBridge, UniswapV3Bridge {
    using SafeERC20 for IERC20;

    /*
        STRUCTS AND ENUMS
    */

    //used as a record for MINT_PT1 & MINT_P2
    struct MintFunding {
        address token;
        uint256 amount;
    }

    error InvalidCaller();
    error InvalidOutputs();
    error InvalidRefund();
    /* 
        IMMUTABLES
    */

    /* 
        MUTABLE VARIABLES
    */

    mapping(uint256 => MintFunding) public syncMintFundingMap; //interaction nonce -> MintFunding struct for MINT_PT1 interactions

    modifier onlyRollup() {
        if (msg.sender != address(ROLLUP_PROCESSOR)) revert InvalidCaller();
        _;
    }

    constructor(
        address _rollupProcessor,
        address _router,
        address _nonfungiblePositionManager,
        address _factory,
        address _wEth
    ) public UniswapV3Bridge(_rollupProcessor, _router, _nonfungiblePositionManager, _factory, _wEth) {}

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
     * @notice this function is used to check whether an AztecAsset is an ERC20 or ETH.
     * @dev If it is ETH,
     * then the underlying ETH is wrapped and the function returns the WETH address (since inputAsset.erc20Address returns 0 if
     * the underlying is ETH). Otherwise it returns 0.
     * @param _inputAsset The uint64 to be unpacked
     * @return address the address of the asset, WETH if it is ETH, else erc20 address, or 0 if it is neither
     */

    function _checkForType(AztecTypes.AztecAsset calldata _inputAsset) internal returns (address) {
        if (_inputAsset.assetType == AztecTypes.AztecAssetType.ETH) {
            WETH.deposit{value: msg.value}();
            return address(WETH);
        } else if (_inputAsset.assetType == AztecTypes.AztecAssetType.ERC20) {
            return _inputAsset.erc20Address;
        } else {
            return address(0); //return the 0 address as a substitute for false
        }
    }

    /**
     * @notice This function performs 4 different types of interactions.
     * @dev  Step 1 of minting a liquidity position. Step 2 of minting a
     * liquidity position. Or the mint-by-swap interaction for 1 step liquidity position minting. Lastly, redemption of liquidity for
     * underlying. The interactions are completed in some cases within the function, and sometimes by calls to internal functions
     * where the logic is performed.
     * @param _inputAssetA AztecAsset
     * @param _inputAssetB AztecAsset
     * @param _outputAssetA AztecAsset
     * @param _outputAssetB AztecAsset
     * @return outputValueA output of _outputAssetA
     * @return outputValueB output of _outputAssetB
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
            bool isAsync
        )
    {
        //require(inputValue == 0, "ZERO");

        if (!(msg.sender == address(ROLLUP_PROCESSOR) || msg.sender == address(this))) revert InvalidCaller();

        //INTERACTION TYPE 1
        //1 real 1 not used
        //1 virtual 1 not used

        if (
            _outputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED &&
            _checkForType(_inputAssetA) != address(0) &&
            _inputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL
        ) {
            //sanity check
            address inputAddress = _checkForType(_inputAssetA);

            //state changes
            syncMintFundingMap[_interactionNonce] = MintFunding({token: inputAddress, amount: _inputValue});
            //_outputAssetA.id = _interactionNonce;
            //_outputAssetA.erc20Address = inputAddress;
            outputValueA = _inputValue;
            //            console.log("finished");
        }
        //INTERACTION TYPE 2
        //1 real 1 virtual
        //1 virtual 1 real (refund)
        else if (
            _inputAssetB.assetType == AztecTypes.AztecAssetType.VIRTUAL &&
            _checkForType(_inputAssetA) != address(0) &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL &&
            _checkForType(_outputAssetB) != address(0)
        ) {
            //minting LP position
            //sanity checks + variable instantiation
            address inputAddress = _checkForType(_inputAssetA);
            address refundAddress = _checkForType(_outputAssetB); // this asset is used for refunds

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
            _checkForType(_inputAssetA) != address(0) &&
            _outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL &&
            _checkForType(_outputAssetB) != address(0)
        ) {
            //sanity check
            //note: _outputAssetB's address is assumed to be the secondary address necessary to retrieve the pool, but also for
            //any refunds , if necessary
            address inputAddress = _checkForType(_inputAssetA);
            address outputAddress = _checkForType(_outputAssetB);

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
            _checkForType(_outputAssetA) != address(0) &&
            _inputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED &&
            _inputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL &&
            _checkForType(_outputAssetB) != address(0)
        ) {
            //withdrawing LP

            //sanity check
            uint256 id = _inputAssetA.id; //avoid stack too deep
            address tokenA = _checkForType(_outputAssetA);
            address tokenB = _checkForType(_outputAssetB);

            console.log(tokenA, tokenB);
            {
                // less storage reads
                address token0 = deposits[id].token0;
                address token1 = deposits[id].token1;
                console.log(token0, token1);
                bool validArgs = (tokenA == token0 && token1 == tokenB) || (tokenB == token0 && token1 == tokenA);
                if (!validArgs) revert InvalidOutputs();
            }

            //state changes
            (outputValueA, outputValueB) = _withdraw(id, uint128(_inputValue));
            //done because _decreaseLiquidity spits out amount0 amount1 and A && B not necessariy == token0 && token1
            if (!(tokenA == deposits[id].token0)) {
                (outputValueA, outputValueB) = (outputValueB, outputValueA);
            }

            IERC20(tokenA).safeIncreaseAllowance(address(ROLLUP_PROCESSOR), outputValueA);
            IERC20(tokenB).safeIncreaseAllowance(address(ROLLUP_PROCESSOR), outputValueB);
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
        {
            //address pool = uniswapFactory.getPool(inputAddress, syncMintFundingMap[_inputAssetB.id].token, uint24(fee) )
            //require(pool != address(0), "NONEXISTENT_POOL");
        }

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
            //console.log("minting");
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
            //console.log("refunding");
            outputValueB = token[0] == _refund ? refund0 : refund1;
            uint256 amountOut = _refundConversion(refund0, refund1, _refund, token[0], token[1], fee);
            outputValueB = outputValueB + amountOut;
        }

        //console.log("passed");
        //note: we need to destroy record of MINT_PT1 funding to avoid virtual asset re-use
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

        {
            console.log("before swap");
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

            console.log("after swap");
            amounts[0] = _input < _output ? _inputValue / 2 : amountOut;
            amounts[1] = _input < _output ? amountOut : _inputValue / 2;
            //            console.log(amounts[0], "amount0");
            //            console.log(amounts[1], "amount1");
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
        if ((refund1 > 0 && _output == token0) || (refund0 > 0 && _output == token1)) {
            outputValueB = token0 == _output ? refund0 : refund1;
            amounts[0] = _refundConversion(refund0, refund1, _output, token0, token1, fee);
            outputValueB = outputValueB + amounts[0];
        }

        TransferHelper.safeApprove(_output, address(ROLLUP_PROCESSOR), outputValueB);
    }

    function canFinalise(uint256 _interactionNonce) external view onlyRollup returns (bool) {
        return false;
    }

    function finalise(
        AztecTypes.AztecAsset calldata _inputAssetA,
        AztecTypes.AztecAsset calldata _inputAssetB,
        AztecTypes.AztecAsset calldata _outputAssetA,
        AztecTypes.AztecAsset calldata _outputAssetB,
        uint256 _interactionNonce,
        uint64 _auxData
    )
        external
        payable
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool interactionComplete
        )
    {
        revert("NOT_ASYNC");
    }
}
