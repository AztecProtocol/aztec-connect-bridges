# @version >=0.3.6

"""
@title  A bridge for entering and exiting a Curve LP position for the eth/STETH pool
@licence Apache-2.0
@author Aztec team
@notice You can use this bridge to enter or exit positions on the eth/STETH pool
        Can be entered with either eth or STETH, but will always exit with both.
"""

from vyper.interfaces import ERC20

interface IRollupProcessor:
    def receiveEthFromBridge(_interactionNonce: uint256): payable

interface ICurvePool:
    def add_liquidity(amounts: uint256[2], min_mint_amount: uint256) -> uint256: payable
    def remove_liquidity(_amount: uint256, _min_amounts: uint256[2]) -> uint256[2]: nonpayable
    def lp_token() -> address: view

interface IWstETh:
    def unwrap(val: uint256) -> uint256: nonpayable
    def wrap(val: uint256) -> uint256: nonpayable

interface ISubsidy:
    def claimSubsidy(_criteria: uint256, _beneficiary: address)-> uint256: nonpayable
    def setGasUsageAndMinGasPerMinute(_criteria: uint256, _gasUsage: uint32, _minGasPerminute: uint32): nonpayable

struct AztecAsset:
    id: uint256
    erc20Address: address
    assetType: uint8 # solidity and vyper enums differ, (NON_USED, ETH, ERC20, VIRTUAL)

STETH: constant(address) = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84
WSTETH: constant(address) = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0
CURVE_POOL: constant(address) = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022
SUBSIDY: constant(address) = 0xABc30E831B5Cc173A9Ed5941714A7845c909e7fA
CURVE_ETH_INDEX: constant(int128) = 0
CURVE_STETH_INDEX: constant(int128) = 1
PRICE_PRECISION: constant(uint256) = 1000000

LP_TOKEN: immutable(address)
ROLLUP_PROCESSOR: immutable(address)

@external
def __init__(_rollupProcessor: address):
    """
    @notice Store address of the rollup processor and LPToken and perform pre-approvals
    @dev    Because the bridge wont hold funds after an interaction, pre-approvals can be
            used to save gas.
    """
    ROLLUP_PROCESSOR = _rollupProcessor
    LP_TOKEN = ICurvePool(CURVE_POOL).lp_token()

    val: uint256 = max_value(uint256)
    ERC20(STETH).approve(CURVE_POOL, val, default_return_value = True)
    ERC20(STETH).approve(WSTETH, val, default_return_value = True)
    ERC20(LP_TOKEN).approve(ROLLUP_PROCESSOR, val, default_return_value = True)
    ERC20(WSTETH).approve(ROLLUP_PROCESSOR, val, default_return_value = True)

    ISubsidy(SUBSIDY).setGasUsageAndMinGasPerMinute(0, 250000, 180)
    ISubsidy(SUBSIDY).setGasUsageAndMinGasPerMinute(1, 250000, 180)

@payable
@external
def __default__():
    """
    @notice Default used to accept Eth from pool when exiting
    """
    pass

@payable
@external
def convert_11192637865(
    _inputAssetA: AztecAsset,
    _inputAssetB: AztecAsset,
    _outputAssetA: AztecAsset,
    _outputAssetB: AztecAsset,
    _totalInputValue: uint256,
    _interactionNonce: uint256,
    _auxData: uint64,
    _rollupBeneficiary: address
) -> (uint256, uint256, bool):
    """
    @notice Function called by the defi proxy, executes deposit or withdrawal depending on input 
    @dev    Instead of `convert` named `convert_11192637865` to work around the `convert` keyword
            while still having the same selector.
    @param  _inputAssetA - The first Aztec Asset to input the call, will be LPToken or eth or WSTETH
    @param  _inputAssetB - Always empty for this bridge
    @param  _outputAssetA - The first aztec asset to receive from the call, will be LPToken or eth
    @param  _outputAssetB - The second aztec asset to receive from the call, will be none or WSTETH
    @param  _totalInputValue - The amount of token to deposit or withdraw
    @param  _interactionNonce - The unique identifier for this defi interaction
    @param  _auxData - Auxiliary data that can be used by the bridge
    @param  _rollupBeneficiary - The address of the beneficiary of subsidies
    @return outputValueA - The amount of outputAssetA that the rollup should pull
    @return outputValueB - The amount of outputAssetB that the rollup should pull
    @return isAsync - True if the bridge is async, false otherwise. Always false for this bridge
    """
    assert msg.sender == ROLLUP_PROCESSOR, "Invalid caller"

    if _inputAssetB.assetType != 0:
        raise "Invalid asset B"

    # Eth or WSTETH in -> LPToken out
    deposit: bool = (_inputAssetA.assetType == 1 or (_inputAssetA.assetType == 2 and _inputAssetA.erc20Address == WSTETH)) and _outputAssetA.assetType == 2 and _outputAssetA.erc20Address == LP_TOKEN

    # LPToken in -> eth + WSTETH out
    withdraw: bool = _inputAssetA.assetType == 2 and _inputAssetA.erc20Address == LP_TOKEN and _outputAssetA.assetType == 1 and _outputAssetB.assetType == 2 and _outputAssetB.erc20Address == WSTETH

    if not((deposit or withdraw) and not(deposit and withdraw)):
        raise "Invalid assets"

    if deposit:
        return self._deposit(_totalInputValue, _inputAssetA.assetType == 1, _auxData, _rollupBeneficiary)
    return self._withdraw(_totalInputValue, _interactionNonce, _auxData, _rollupBeneficiary)

@external
@view
def get_lp_token() -> address:
    return LP_TOKEN

@external
@view 
def get_rollup_processor() -> address:
    return ROLLUP_PROCESSOR

@external
@view
def computeCriteria(
    _inputAssetA: AztecAsset,
    _inputAssetB: AztecAsset,
    _outputAssetA: AztecAsset,
    _outputAssetB: AztecAsset,
    _auxData: uint64
) -> uint256:
    """
    @notice Computes the criteria used for claiming subsidy
    @dev    Criteria is computed based only on the `_inputAssetA`
    @param  _inputAssetA - The first Aztec Asset to input the call, will be (LPToken or eth or WSTETH)
    @param  _inputAssetB - Always empty for this bridge
    @param  _outputAssetA - The first aztec asset to receive from the call, will be (LPToken or eth)
    @param  _outputAssetB - The second aztec asset to receive from the call, will be (none or WSTETH)
    @param  _auxData - The auxdata 
    @return The criteria, 1 if exiting, 0 otherwise
    """
    if _inputAssetA.erc20Address == LP_TOKEN:
        return 1
    return 0

@internal
def _deposit(_value: uint256, _isEthInput: bool, _auxData: uint64, _beneficiary: address) -> (uint256, uint256, bool):
    """
    @notice Perform a deposit (adding liquidity) to the curve pool
    @param  _value - The amount of token to deposit
    @param  _isEthInput - A flag describing whether Eth is used as input or not
    @param  _auxData - The amount of LP token per one eth or STETH (not WSTETH) with precision 1e6
    @param  _beneficiary - The address of the subsidy beneficiary
    @dev    When Eth is not the input, input must be WSTETH, which is unwrapped before adding liquidity
    @return outputValueA - The amount of LP-token to receive 
    @return outputValueB - Always zero for this bridge
    @return isAsync - Always false for this bridge
    """
    outputValueA: uint256 = 0
    amounts: uint256[2] = [0, 0]

    if _isEthInput:
        amounts[CURVE_ETH_INDEX] = _value
        minOut: uint256 = (amounts[CURVE_ETH_INDEX] * convert(_auxData, uint256)) / PRICE_PRECISION

        outputValueA = ICurvePool(CURVE_POOL).add_liquidity(amounts, minOut, value = _value)
    else:
        amounts[CURVE_STETH_INDEX] = IWstETh(WSTETH).unwrap(_value)
        minOut: uint256 = (amounts[CURVE_STETH_INDEX] * convert(_auxData, uint256)) / PRICE_PRECISION

        outputValueA = ICurvePool(CURVE_POOL).add_liquidity(amounts, minOut)
    ISubsidy(SUBSIDY).claimSubsidy(0, _beneficiary)
    return (outputValueA, 0, False)

@internal
def _withdraw(_value: uint256, _interactionNonce: uint256, _auxData: uint64, _beneficiary: address) -> (uint256, uint256, bool):
    """
    @notice Performs a withdrawal from LP-token to (eth, WSTETH)
    @dev    Will exit to eth and STETH, and then wrap the STETH before returning
    @param  _value - The amount of LP-token to withdraw
    @param  _interactionNonce - The unique identifier of the defi interaction
    @param  _auxData - The amount of `eth` AND `STETH` per LPToken with precision 1e6. Encoded as two 32 
            bit values. 
    @param  _beneficiary - The address of the subsidy beneficiary
    @return outputValueA - The amount of eth to retrieve
    @return outputBalueB - The amount of WSTETH to retrive
    @return isAsync - Always false for this bridge
    """
    minAmounts: uint256[2] = [0, 0]
    minAmounts[CURVE_ETH_INDEX] = _value * (convert(_auxData, uint256) & (2**32 - 1)) / PRICE_PRECISION
    minAmounts[CURVE_STETH_INDEX] = _value * (shift(convert(_auxData, uint256), -32) & (2**32 - 1)) / PRICE_PRECISION

    amounts: uint256[2] = ICurvePool(CURVE_POOL).remove_liquidity(_value, minAmounts)
    wstEthAmount: uint256 = IWstETh(WSTETH).wrap(amounts[1])
    IRollupProcessor(ROLLUP_PROCESSOR).receiveEthFromBridge(_interactionNonce, value = amounts[0])
    ISubsidy(SUBSIDY).claimSubsidy(1, _beneficiary)
    return (amounts[0], wstEthAmount, False)