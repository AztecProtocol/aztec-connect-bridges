
// SPDX-License-Identifier: GPL-2.0-only
// Copyright 2020 Spilsbury Holdings Ltd
pragma solidity >=0.6.10 <=0.8.10;
pragma abicoder v2;


import {IERC20Detailed, IERC20} from "./interfaces/IERC20.sol";
import {AztecTypes} from '../../aztec/AztecTypes.sol';
import './UniswapV3Bridge.sol';
import "./interfaces/IUniswapV3Pool.sol";
import '../../interfaces/IDefiBridge.sol';
import "./interfaces/IQuoter.sol";

contract SyncUniswapV3Bridge is IDefiBridge, UniswapV3Bridge {
    
    using SafeMath for uint256;



    /* 
        STRUCTS AND ENUMS
    */

    //used as a record for MINT_PT1 & MINT_P2
    struct MintFunding {
        address token;
        uint256 amount;
    }

    /* 
        IMMUTABLES
    */

    IQuoter public immutable quoter;
    
    /* 
        MUTABLE VARIABLES
    */

    mapping(uint256 => MintFunding) public SyncMintFundingMap; //interaction nonce -> MintFunding struct for MINT_PT1 interactions


    constructor(address _rollupProcessor, address _router, address _nonfungiblePositionManager, address _factory, address _WETH, address _quoter) 
    UniswapV3Bridge( _rollupProcessor, _router, _nonfungiblePositionManager, _factory, _WETH) public {
        quoter = IQuoter(_quoter);
    }

    modifier onlyRollup {
    require(msg.sender == address(rollupProcessor), "INVALID_CALLER");
    _;
    }

    /**
     * @notice  packs auxData for front end user
     * @dev The first 24 bits are tickLower. The second 24 are tickUpper. The last 16 the pool's fee.
     * As a pool's fee ranges from 10 bps, 100 bps, 300 bps, and 1000 bps, there is no data loss and type conversion
     * is acceptable.
     * @param tickLower the lower range of the position
     * @param tickUpper the upper range of the position
     * @param fee the fee tier of the pool
     * @return auxData the packed auxdata
     */

    function packData(int24 tickLower, int24 tickUpper, uint24 fee) external view returns (uint64 auxData) {
            uint24 a = uint24(tickLower);
            uint24 b = uint24(tickUpper);
            uint48 ticks = (uint48(a) << 24) | uint48(b);
            uint16 fee =  uint16(fee);
            auxData = (uint64(ticks) << 16) | uint64(fee);
    }
    
    /**
     * @notice  Functions are used to unpack auxData in chunks of 24 or 16 bits.
     * @dev The first 24 bits are tickLower. The second 24 are tickUpper. The last 16 the pool's fee.
     * As a pool's fee ranges from 10 bps, 100 bps, 300 bps, and 1000 bps, there is no data loss and type conversion
     * is acceptable.
     * @param a The uint64 to be unpacked
     * @return b the uint24 or uint16
     */

    function unpack_1_to_24(uint64 a) public pure returns(uint24 b) {
       b = uint24(a >> 40);
    }

    function unpack_24_to_48(uint64 a) public pure returns (uint24 b){
        b = uint24(a >> 16);
    }
    function unpack_48_to_64(uint64 a) public pure returns (uint16 b){
        b = uint16(a);
    }

    /**
     * @notice this function is used to check whether an AztecAsset is an ERC20 or ETH.
     * @dev If it is ETH, 
     * then the underlying ETH is wrapped and the function returns the WETH address (since inputAsset.erc20Address returns 0 if
     * the underlying is ETH). Otherwise it returns 0.
     * @param inputAsset The uint64 to be unpacked
     * @return address the address of the asset, WETH if it is ETH, else erc20 address, or 0 if it is neither
     */

    function _checkForType(AztecTypes.AztecAsset calldata inputAsset) internal returns (address){
        if(inputAsset.assetType == AztecTypes.AztecAssetType.ETH){
            WETH.deposit{value: msg.value}();
            return address(WETH);
        }
        else if(inputAsset.assetType == AztecTypes.AztecAssetType.ERC20){
            return inputAsset.erc20Address;
        }
        else{
            return address(0); //return the 0 address as a substitute for false
        }
    }

    /**
     * @notice This function performs 4 different types of interactions.
     * @dev  Step 1 of minting a liquidity position. Step 2 of minting a 
     * liquidity position. Or the mint-by-swap interaction for 1 step liquidity position minting. Lastly, redemption of liquidity for
     * underlying. The interactions are completed in some cases within the function, and sometimes by calls to internal functions
     * where the logic is performed. 
     * @param inputAssetA AztecAsset
     * @param inputAssetB AztecAsset
     * @param outputAssetA AztecAsset
     * @param outputAssetB AztecAsset
     * @return outputValueA output of outputasseta
     * @return outputValueB output of outputassetb
     */
         
    function convert(
        AztecTypes.AztecAsset calldata inputAssetA,
        AztecTypes.AztecAsset calldata inputAssetB, 
        AztecTypes.AztecAsset calldata outputAssetA,
        AztecTypes.AztecAsset calldata outputAssetB,
        uint256 inputValue,
        uint256 interactionNonce, 
        uint64  auxData,
        address
    )
        external
        payable
        override
        returns (
            uint256 outputValueA,
            uint256 outputValueB,
            bool isAsync
        )
    {

        //require(inputValue == 0, "ZERO");
        require(msg.sender == address(rollupProcessor) || msg.sender == address(this), 'UniswapV3Bridge: INVALID_CALLER');

        //INTERACTION TYPE 1 
        //1 real 1 not used
        //1 virtual 1 not used

        if (
            outputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED &&
            _checkForType(inputAssetA) != address(0) && inputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED &&
            outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL  
            ) 
        {

            //sanity check
            address input_address = _checkForType(inputAssetA);

            //state changes
            SyncMintFundingMap[interactionNonce] = MintFunding({
                token:  input_address,
                amount: inputValue
            });
            //outputAssetA.id = interactionNonce;
            //outputAssetA.erc20Address = input_address;
            outputValueA = inputValue;
//            console.log("finished");
        }
        //INTERACTION TYPE 2 
        //1 real 1 virtual
        //1 virtual 1 real (refund)
        else if(  inputAssetB.assetType == AztecTypes.AztecAssetType.VIRTUAL && _checkForType(inputAssetA) != address(0) && 
                outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL && _checkForType(outputAssetB) != address(0)                     
        ) {
            
            //minting LP position
            //sanity checks + variable instantiation
            address input_address = _checkForType(inputAssetA);
            address refund_address = _checkForType(outputAssetB); // this asset is used for refunds
            require( input_address ==  refund_address ||  refund_address == SyncMintFundingMap[inputAssetB.id].token, "INVALID_REFUND");
            

            (outputValueA, outputValueB) = _convertMintPart2(input_address, refund_address, interactionNonce, inputAssetB.id, inputValue, auxData);
        
        }
        //INTERACTION TYPE 3
        //1 real 1 not used
        //1 virtual 1 real (the second pair)
        else if(  inputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED && _checkForType(inputAssetA) != address(0) && 
                 outputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL && _checkForType(outputAssetB) != address(0) ){

            //sanity check
            //note: outputAssetB's address is assumed to be the secondary address necessary to retrieve the pool, but also for
            //any refunds , if necessary
            address input_address = _checkForType(inputAssetA); 
            address output_address = _checkForType(outputAssetB);
            
            (outputValueA, outputValueB) = _convertMintBySwap(input_address, output_address, interactionNonce, inputValue, auxData);

        }
        //INTERACTION TYPE 4 
        //1 virtual 1 not used
        //1 real 1 real
        else if( _checkForType(outputAssetA) != address(0) && inputAssetB.assetType == AztecTypes.AztecAssetType.NOT_USED 
          && inputAssetA.assetType == AztecTypes.AztecAssetType.VIRTUAL && _checkForType(outputAssetB) != address(0) )
        {

            //withdrawing LP
        
            //sanity check
            uint256 id = inputAssetA.id; //avoid stack too deep
            address A = _checkForType(outputAssetA); 
            address B = _checkForType(outputAssetB);


            {
                // less storage reads
                address token0 = deposits[id].token0;
                address token1 = deposits[id].token1;

                bool valid_args = ( (A == token0  && token1 == B) ||
                                    (B == token0 && token1 == A) );
                require(valid_args,"INVALID_OUTPUTS");
            }
            

            //state changes
            (outputValueA, outputValueB) = _withdraw(id, uint128(inputValue) );
            //done because _decreaseLiquidity spits out amount0 amount1 and A && B not necessariy == token0 && token1
            if(!(A == deposits[id].token0 ) )
            { (outputValueA, outputValueB) = (outputValueB, outputValueA); }

            if( inputAssetA.assetType == AztecTypes.AztecAssetType.ETH ) {
                ERC20NoReturnApprove(B,address(rollupProcessor), outputValueB);
                TransferHelper.safeApprove(A,address(rollupProcessor), outputValueA);
                WETH.withdraw(outputValueA);
                rollupProcessor.receiveEthFromBridge{value: outputValueA}(interactionNonce);
            
            }
            else if(inputAssetB.assetType == AztecTypes.AztecAssetType.ETH ){  
                TransferHelper.safeApprove(B,address(rollupProcessor), outputValueB);
                ERC20NoReturnApprove(A,address(rollupProcessor), outputValueA);
                WETH.withdraw(outputValueB);
                rollupProcessor.receiveEthFromBridge{value: outputValueB}(interactionNonce);

            }
            else {
                ERC20NoReturnApprove(B,address(rollupProcessor), outputValueB);
                ERC20NoReturnApprove(A,address(rollupProcessor), outputValueA);
            }
        }
    }
    
    /**
     * @notice internal function to perform part 2 of the 2-step minting interaction
     * @dev performs some checks, unpacks the params, then mints a new position. handles refunding at the end. 
     * @param input address of the input asset
     * @param refund address of the output/refund asset
     * @param interactionNonce the interactionnonce
     * @param id the interactionNonce of the virtual asset provided in the convert call, which is used to prove ownersip 
     * of an interaction that provided funding in step 1 for this step.
     * @param inputValue the input size of inputAssetA.
     * @param params the params, including the tickLower, the tickUpper, and the pool's fee.
     * @return outputValueA outputvalueA , liquidity minted
     * @return outputValueB outputvalueb, the refund
     */
    
    function _convertMintPart2(address input, address refund, uint256 interactionNonce, uint256 id, uint256 inputValue, uint64 params) internal returns (uint256 outputValueA, uint256 outputValueB) 
    {

            
        {
            
            //address pool = uniswapFactory.getPool(input_address, SyncMintFundingMap[inputAssetB.id].token, uint24(fee) )
            //require(pool != address(0), "NONEXISTENT_POOL");
                
        }


        address[] memory token = new address[](2);

        {
            //avoid stack too deep and avoids 3 reads to storage
            address deposited = SyncMintFundingMap[id].token;
            token[0] =  input < deposited ? input :  deposited;
            token[1] =  input < deposited ? deposited :  input;
        }

        //state changes
        //outputAssetA.id = interactionNonce;
            
        uint24 fee;
        uint256 refund0;
        uint256 refund1;
        
        {
            //avoid stack too deep
            uint256 amount0 = token[0] == input ? inputValue : SyncMintFundingMap[id].amount;
            uint256 amount1 = token[0] == input ? SyncMintFundingMap[id].amount : inputValue;
            uint256 stackholder_nonce = interactionNonce;
            //outputValueA = liquidity here
            fee = uint24(unpack_48_to_64(params)); 
            int24 tickLower = int24(unpack_1_to_24(params));
            int24 tickUpper = int24(unpack_24_to_48(params));
            //console.log("minting");
            (outputValueA, refund0, refund1) = _mintNewPosition( token[0],  token[1], 
            amount0, amount1, tickLower, tickUpper, fee, stackholder_nonce);
        }

        //refunding
        if(refund1 > 0 &&  refund == token[0] || refund0 > 0 &&  refund ==  token[1] ){
            //console.log("refunding");
            outputValueB = token[0] ==  refund ? refund0 : refund1;
            uint256 amountOut = _refundConversion(refund0,refund1, refund ,token[0], token[1],fee);
            outputValueB = outputValueB.add(amountOut);
        }

        //console.log("passed");
        //note: we need to destroy record of MINT_PT1 funding to avoid virtual asset re-use
        SyncMintFundingMap[id].amount = 0;
       
        //approve rollupProcessor to receive refund

        TransferHelper.safeApprove(refund, address(rollupProcessor), outputValueB);

 

    }

    /**
     * @notice internal function to perform the mint-by-swap interaction
     * @dev swaps half of the input. Mints a new position, and handles refunding.
     * @param input the input asset's address
     * @param output the output asset's address
     * @param interactionNonce the interaction nonce
     * @param inputValue the size of the input asset
     * @param params the params for the liquidity position, i.e. tickLower, tickUpper, and the pool fee.
     * @return outputValueA the liquidity minted
     * @return outputValueB the refund if any
     */

    function _convertMintBySwap(address input, address output, uint256 interactionNonce, uint256 inputValue, uint64 params) internal returns (uint256 outputValueA, uint256 outputValueB)
    {

        uint256[] memory amounts = new uint256[](2);
        uint24 fee = uint24(unpack_48_to_64(params));


        {

            ERC20NoReturnApprove(input, address(swapRouter),inputValue/2);
            ISwapRouter.ExactInputSingleParams memory swap_params =
            ISwapRouter.ExactInputSingleParams({
                tokenIn:  input,
                tokenOut: output,
                fee: fee,
                recipient: address(this), 
                deadline: block.timestamp,
                amountIn: inputValue/2,
                amountOutMinimum: 0, //flashbots
                sqrtPriceLimitX96: 0
            });

            uint256 amountOut = swapRouter.exactInputSingle(swap_params);

            amounts[0] =  input < output ? inputValue/2 : amountOut;
            amounts[1] =  input < output ? amountOut : inputValue/2;
//            console.log(amounts[0], "amount0");
//            console.log(amounts[1], "amount1");

        }

        //outputAssetA.id = interactionNonce;
        uint256 refund0;
        uint256 refund1;
        address token0 =  input < output ? input :  output;
        address token1 =  input < output ? output :  input;       

        {
            uint256 stackholder_nonce = interactionNonce; //avoid stack too deep
            int24 tickLower = int24(unpack_1_to_24(params));
            int24 tickUpper = int24(unpack_24_to_48(params));
            (outputValueA , refund0, refund1) = _mintNewPosition(token0, token1, amounts[0],amounts[1],tickLower,tickUpper,fee,stackholder_nonce);
        }


        //refunding
        if(refund1 > 0 && output == token0 || refund0 > 0 && output == token1 ){
            outputValueB = token0 == output ? refund0 : refund1;
            amounts[0] = _refundConversion(refund0,refund1,output,token0,token1,fee);
            outputValueB = outputValueB.add(amounts[0]);
        }

        TransferHelper.safeApprove(output, address(rollupProcessor), outputValueB );

    }
    
    function canFinalise(
        uint256 interactionNonce
    ) external view onlyRollup returns (bool) {
        return false;
    }

    function finalise(
    AztecTypes.AztecAsset calldata inputAssetA,
    AztecTypes.AztecAsset calldata inputAssetB,
    AztecTypes.AztecAsset calldata outputAssetA,
    AztecTypes.AztecAsset calldata outputAssetB,
    uint256 interactionNonce,
    uint64 auxData
    ) external payable returns (uint256 outputValueA, uint256 outputValueB, bool interactionComplete){
    revert("NOT_ASYNC");
    }


}